WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 64 AND 74
),
aspirin_prescriptions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%aspirin%' 
    OR LOWER(drug) LIKE '%asa%'
),
p2y12_prescriptions AS (
  SELECT 
    hadm_id, 
    starttime, 
    stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%clopidogrel%'
    OR LOWER(drug) LIKE '%ticagrelor%'
    OR LOWER(drug) LIKE '%prasugrel%'
),
admissions_with_both AS (
  SELECT 
    c.*
  FROM cohort c
  WHERE 
    EXISTS (SELECT 1 FROM aspirin_prescriptions a WHERE a.hadm_id = c.hadm_id)
    AND EXISTS (SELECT 1 FROM p2y12_prescriptions p WHERE p.hadm_id = c.hadm_id)
),
p2y12_aggregated AS (
  SELECT 
    a.hadm_id,
    MIN(p.starttime) AS first_start,
    MAX(p.stoptime) AS last_stop,
    ANY_VALUE(a.admittime) AS admittime,
    ANY_VALUE(a.dischtime) AS dischtime
  FROM admissions_with_both a
  INNER JOIN p2y12_prescriptions p
    ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id
),
therapy_duration AS (
  SELECT 
    hadm_id,
    GREATEST(first_start, admittime) AS therapy_start,
    LEAST(COALESCE(last_stop, dischtime), dischtime) AS therapy_end,
    TIMESTAMP_DIFF(
      LEAST(COALESCE(last_stop, dischtime), dischtime),
      GREATEST(first_start, admittime),
      SECOND
    ) / 86400.0 AS duration_days
  FROM p2y12_aggregated
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM therapy_duration;