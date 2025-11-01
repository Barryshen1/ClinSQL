WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.gender,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 57 AND 67
),

transplant_codes AS (
  -- ICD-9 V42.x, ICD-10 Z94.x
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code LIKE 'V42%')
    OR (icd_version = 10 AND icd_code LIKE 'Z94%')
),

transplant_status AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN transplant_codes tc
        ON d.icd_code = tc.icd_code AND d.icd_version = tc.icd_version
      WHERE d.hadm_id = c.hadm_id
    ) THEN 'Transplant' ELSE 'Non-Transplant' END AS transplant_status,
    c.intime,
    c.outtime,
    c.los
  FROM cohort c
),

itemids AS (
  SELECT
    MAX(CASE WHEN LOWER(label) LIKE '%temperature%' AND LOWER(unitname) LIKE '%celsius%' THEN itemid END) AS temp_itemid,
    MAX(CASE WHEN (LOWER(label) LIKE '%o2 saturation%' OR LOWER(label) LIKE '%spo2%') THEN itemid END) AS spo2_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%respiratory rate%' THEN itemid END) AS rr_itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
),

instability_events AS (
  SELECT
    ts.stay_id,
    -- Fever >38.5°C
    COUNTIF(
      ce.itemid = ids.temp_itemid
      AND ce.valuenum > 38.5
      AND ce.charttime BETWEEN ts.intime AND TIMESTAMP_ADD(ts.intime, INTERVAL 72 HOUR)
    ) AS fever_events,
    -- SpO2 <90%
    COUNTIF(
      ce.itemid = ids.spo2_itemid
      AND ce.valuenum < 90
      AND ce.charttime BETWEEN ts.intime AND TIMESTAMP_ADD(ts.intime, INTERVAL 72 HOUR)
    ) AS spo2_events,
    -- RR >20
    COUNTIF(
      ce.itemid = ids.rr_itemid
      AND ce.valuenum > 20
      AND ce.charttime BETWEEN ts.intime AND TIMESTAMP_ADD(ts.intime, INTERVAL 72 HOUR)
    ) AS rr_events
  FROM transplant_status ts
  CROSS JOIN itemids ids
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = ts.stay_id
    AND ce.itemid IN (ids.temp_itemid, ids.spo2_itemid, ids.rr_itemid)
    AND ce.valuenum IS NOT NULL
  GROUP BY ts.stay_id
),

final AS (
  SELECT
    ts.transplant_status,
    ts.stay_id,
    ts.los,
    COALESCE(ev.fever_events, 0) + COALESCE(ev.spo2_events, 0) + COALESCE(ev.rr_events, 0) AS instability_score,
    ts.hadm_id,
    ts.subject_id
  FROM transplant_status ts
  LEFT JOIN instability_events ev
    ON ts.stay_id = ev.stay_id
),

mortality AS (
  SELECT
    hadm_id,
    MAX(hospital_expire_flag) AS died
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY hadm_id
)

SELECT
  f.transplant_status,
  COUNT(*) AS n_stays,
  APPROX_QUANTILES(f.instability_score, 4)[OFFSET(2)] AS median_instability_score,
  APPROX_QUANTILES(f.instability_score, 4)[OFFSET(1)] AS p25_instability_score,
  APPROX_QUANTILES(f.instability_score, 4)[OFFSET(3)] AS p75_instability_score,
  APPROX_QUANTILES(f.los, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(f.los, 4)[OFFSET(1)] AS p25_los,
  APPROX_QUANTILES(f.los, 4)[OFFSET(3)] AS p75_los,
  ROUND(100 * SUM(m.died)/COUNT(*),1) AS mortality_rate
FROM final f
LEFT JOIN mortality m
  ON f.hadm_id = m.hadm_id
GROUP BY f.transplant_status
ORDER BY f.transplant_status;