WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd1
    ON d1.icd_code = dd1.icd_code AND d1.icd_version = dd1.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
    ON d2.icd_code = dd2.icd_code AND d2.icd_version = dd2.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      dd1.icd_code LIKE 'E10%'
      OR dd1.icd_code LIKE 'E11%'
      OR dd1.icd_code LIKE 'E14%'
    )
    AND (
      dd2.icd_code LIKE 'I50%'
    )
),

meds_first_48h AS (
  SELECT
    c.subject_id,
    c.stay_id,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(drug) LIKE '%metformin%'
        OR LOWER(drug) LIKE '%glyburide%'
        OR LOWER(drug) LIKE '%glipizide%' THEN 'oral'
    END AS med_type,
    starttime,
    stoptime,
    CASE
      WHEN starttime <= c.intime + INTERVAL 48 HOUR
        AND (stoptime IS NULL OR stoptime >= c.intime) THEN 'continued'
      WHEN starttime BETWEEN c.intime AND c.intime + INTERVAL 48 HOUR THEN 'initiated'
      WHEN stoptime BETWEEN c.intime AND c.intime + INTERVAL 48 HOUR THEN 'discontinued'
    END AS status
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE
    LOWER(drug) LIKE '%insulin%'
    OR LOWER(drug) LIKE '%metformin%'
    OR LOWER(drug) LIKE '%glyburide%'
    OR LOWER(drug) LIKE '%glipizide%'
),

meds_last_24h AS (
  SELECT
    c.subject_id,
    c.stay_id,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(drug) LIKE '%metformin%'
        OR LOWER(drug) LIKE '%glyburide%'
        OR LOWER(drug) LIKE '%glipizide%' THEN 'oral'
    END AS med_type,
    starttime,
    stoptime,
    CASE
      WHEN stoptime IS NULL OR stoptime >= c.outtime - INTERVAL 24 HOUR THEN 'continued'
      WHEN starttime BETWEEN c.outtime - INTERVAL 24 HOUR AND c.outtime THEN 'initiated'
      WHEN stoptime BETWEEN c.outtime - INTERVAL 24 HOUR AND c.outtime THEN 'discontinued'
    END AS status
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE
    LOWER(drug) LIKE '%insulin%'
    OR LOWER(drug) LIKE '%metformin%'
    OR LOWER(drug) LIKE '%glyburide%'
    OR LOWER(drug) LIKE '%glipizide%'
),

first_48h_summary AS (
  SELECT
    med_type,
    status,
    COUNT(*) AS count
  FROM meds_first_48h
  WHERE med_type IS NOT NULL AND status IS NOT NULL
  GROUP BY med_type, status
),

last_24h_summary AS (
  SELECT
    med_type,
    status,
    COUNT(*) AS count
  FROM meds_last_24h
  WHERE med_type IS NOT NULL AND status IS NOT NULL
  GROUP BY med_type, status
)

SELECT
  'First 48h' AS time_window,
  med_type,
  status,
  count
FROM first_48h_summary

UNION ALL

SELECT
  'Last 24h' AS time_window,
  med_type,
  status,
  count
FROM last_24h_summary

ORDER BY time_window, med_type, status;