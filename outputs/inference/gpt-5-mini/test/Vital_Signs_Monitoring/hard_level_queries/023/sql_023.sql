WITH
icu_base AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    p.gender,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    USING(subject_id, hadm_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),
primary_dx AS (
  SELECT d.subject_id, d.hadm_id, d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.seq_num = 1
),
hfnc_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%high flow%'
     OR LOWER(label) LIKE '%high-flow%'
     OR LOWER(label) LIKE '%hfnc%'
     OR LOWER(label) LIKE '%high flow nasal%'
     OR LOWER(label) LIKE '%high flow nasal cannula%'
),
hfnc_events AS (
  SELECT DISTINCT ce.subject_id, ce.hadm_id, ce.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN hfnc_itemids hi ON ce.itemid = hi.itemid
  JOIN icu_base ib ON ib.subject_id = ce.subject_id AND ib.hadm_id = ce.hadm_id AND ib.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN ib.intime AND TIMESTAMP_ADD(ib.intime, INTERVAL 24 HOUR)
  UNION DISTINCT
  SELECT DISTINCT pe.subject_id, pe.hadm_id, pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN hfnc_itemids hi ON pe.itemid = hi.itemid
  JOIN icu_base ib ON ib.subject_id = pe.subject_id AND ib.hadm_id = pe.hadm_id AND ib.stay_id = pe.stay_id
  WHERE pe.starttime BETWEEN ib.intime AND TIMESTAMP_ADD(ib.intime, INTERVAL 24 HOUR)
),
hr_itemids AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
     OR LOWER(label) LIKE '%pulse rate%'
     OR LOWER(label) LIKE '%hr %'
),
sbp_itemids AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
),
hr_meas AS (
  SELECT
    ib.stay_id,
    COUNT(1) AS hr_total,
    SUM(CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_tachy_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_base ib
    ON ce.subject_id = ib.subject_id
   AND ce.hadm_id = ib.hadm_id
   AND ce.stay_id = ib.stay_id
  JOIN hr_itemids hri ON ce.itemid = hri.itemid
  WHERE ce.charttime BETWEEN ib.intime AND TIMESTAMP_ADD(ib.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ib.stay_id
),
sbp_meas AS (
  SELECT
    ib.stay_id,
    COUNT(1) AS sbp_total,
    SUM(CASE WHEN ce.valuenum < 90 THEN 1 ELSE 0 END) AS sbp_hypo_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_base ib
    ON ce.subject_id = ib.subject_id
   AND ce.hadm_id = ib.hadm_id
   AND ce.stay_id = ib.stay_id
  JOIN sbp_itemids sbi ON ce.itemid = sbi.itemid
  WHERE ce.charttime BETWEEN ib.intime AND TIMESTAMP_ADD(ib.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ib.stay_id
),
stay_metrics AS (
  SELECT
    ib.subject_id,
    ib.hadm_id,
    ib.stay_id,
    ib.intime,
    ib.los,
    ib.hospital_expire_flag,
    pd.icd_code AS primary_icd,
    COALESCE(hr.hr_tachy_count, 0) AS hr_tachy_count,
    COALESCE(hr.hr_total, 0) AS hr_total,
    COALESCE(sbp.sbp_hypo_count, 0) AS sbp_hypo_count,
    COALESCE(sbp.sbp_total, 0) AS sbp_total,
    CASE WHEN hr.hr_total > 0 THEN SAFE_DIVIDE(hr.hr_tachy_count, hr.hr_total) ELSE NULL END AS tachy_burden,
    CASE WHEN sbp.sbp_total > 0 THEN SAFE_DIVIDE(sbp.sbp_hypo_count, sbp.sbp_total) ELSE NULL END AS hypotension_burden
  FROM icu_base ib
  LEFT JOIN primary_dx pd ON ib.hadm_id = pd.hadm_id AND ib.subject_id = pd.subject_id
  LEFT JOIN hr_meas hr ON ib.stay_id = hr.stay_id
  LEFT JOIN sbp_meas sbp ON ib.stay_id = sbp.stay_id
),
hfnc_flagged AS (
  SELECT
    sm.*,
    CASE WHEN he.stay_id IS NOT NULL THEN 1 ELSE 0 END AS hfnc_within_24h
  FROM stay_metrics sm
  LEFT JOIN (
    SELECT DISTINCT stay_id FROM hfnc_events
  ) he
  ON sm.stay_id = he.stay_id
),
hfnc_primary_icds AS (
  SELECT DISTINCT primary_icd
  FROM hfnc_flagged
  WHERE hfnc_within_24h = 1
    AND primary_icd IS NOT NULL
),
cohort AS (
  SELECT
    hf.*,
    CASE WHEN hf.tachy_burden IS NULL AND hf.hypotension_burden IS NULL THEN NULL
    ELSE COALESCE(hf.tachy_burden, 0) + COALESCE(hf.hypotension_burden, 0)
    END AS instability_score
  FROM hfnc_flagged hf
  WHERE hf.primary_icd IN (SELECT primary_icd FROM hfnc_primary_icds)
)

SELECT
  g.hfnc_group,
  COUNT(*) AS n_stays,
  -- Instability score quantiles (p25, p50, p75, p95) excluding NULLs via APPROX_QUANTILES
  APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS instability_p25,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS instability_median,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS instability_p75,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS instability_p95,
  -- Median tachycardia burden
  APPROX_QUANTILES(tachy_burden, 100)[OFFSET(50)] AS tachycardia_burden_median,
  -- Median hypotension burden
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(50)] AS hypotension_burden_median,
  -- Median ICU LOS
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS icu_los_median,
  -- Hospital mortality rate
  ROUND(AVG(CAST(g.hospital_expire_flag AS FLOAT64)), 4) AS hospital_mortality_rate
FROM (
  SELECT
    CASE WHEN hfnc_within_24h = 1 THEN 'HFNC_within_24h' ELSE 'Condition_matched_control' END AS hfnc_group,
    instability_score,
    tachy_burden,
    hypotension_burden,
    los,
    hospital_expire_flag
  FROM cohort
) AS g
GROUP BY g.hfnc_group
ORDER BY g.hfnc_group;