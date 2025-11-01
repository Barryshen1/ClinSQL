WITH
base_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los_hours,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),
transplant_diag AS (
  SELECT s.stay_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%transplant%' THEN 1 ELSE 0 END) AS transplant_diag
  FROM base_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = s.subject_id AND di.hadm_id = s.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  GROUP BY s.stay_id
),
transplant_proc AS (
  SELECT s.stay_id,
         MAX(CASE WHEN LOWER(dp.long_title) LIKE '%transplant%' THEN 1 ELSE 0 END) AS transplant_proc
  FROM base_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON pi.subject_id = s.subject_id AND pi.hadm_id = s.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON dp.icd_code = pi.icd_code AND dp.icd_version = pi.icd_version
  GROUP BY s.stay_id
),
stay_with_transplant AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime, s.icu_los_hours, s.gender, s.anchor_age,
         CASE WHEN COALESCE(td.transplant_diag,0) + COALESCE(tp.transplant_proc,0) > 0 THEN 1 ELSE 0 END AS is_transplant
  FROM base_stays s
  LEFT JOIN transplant_diag td ON td.stay_id = s.stay_id
  LEFT JOIN transplant_proc tp ON tp.stay_id = s.stay_id
),
vitals_counts AS (
  SELECT
    st.stay_id,
    SUM(CASE WHEN LOWER(di.label) LIKE '%temperature%' AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_events,
    SUM(CASE WHEN (LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%') AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_events,
    SUM(CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS rr_events
  FROM stay_with_transplant st
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ce.stay_id = st.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
  WHERE ce.charttime BETWEEN st.intime AND TIMESTAMP_ADD(st.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY st.stay_id
),
stay_final AS (
  SELECT s.*,
         COALESCE(v.fever_events, 0) AS fever_events,
         COALESCE(v.spo2_events, 0) AS spo2_events,
         COALESCE(v.rr_events, 0) AS rr_events,
         (COALESCE(v.fever_events,0) + COALESCE(v.spo2_events,0) + COALESCE(v.rr_events,0)) AS instability_score,
         a.hospital_expire_flag AS death_flag
  FROM stay_with_transplant s
  LEFT JOIN vitals_counts v ON v.stay_id = s.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = s.hadm_id
),
final AS (
  SELECT
    CASE WHEN is_transplant = 1 THEN 'Transplant' ELSE 'Non-Transplant' END AS group_label,
    stay_id,
    icu_los_hours,
    instability_score,
    death_flag
  FROM stay_final
),
quant AS (
  SELECT
    group_label,
    COUNT(*) AS n_stays,
    APPROX_QUANTILES(instability_score, 100) AS instability_q,
    APPROX_QUANTILES(icu_los_hours, 100) AS los_q,
    AVG(death_flag) AS mortality_rate
  FROM final
  GROUP BY group_label
)
SELECT
  group_label,
  n_stays,
  instability_q[OFFSET(50)] AS instability_median,
  instability_q[OFFSET(25)] AS instability_q25,
  instability_q[OFFSET(75)] AS instability_q75,
  los_q[OFFSET(50)] AS los_median,
  los_q[OFFSET(25)] AS los_q25,
  los_q[OFFSET(75)] AS los_q75,
  mortality_rate
FROM quant
ORDER BY group_label;