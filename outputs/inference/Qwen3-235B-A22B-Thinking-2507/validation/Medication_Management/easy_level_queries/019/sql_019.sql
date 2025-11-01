WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 58 AND 68
),
prescriptions_filtered AS (
  SELECT 
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE 
    (LOWER(p.drug) LIKE '%heparin%' 
     OR LOWER(p.drug) LIKE '%enoxaparin%' 
     OR LOWER(p.drug) LIKE '%lovenox%')
    AND p.stoptime IS NOT NULL
    AND p.starttime <= p.stoptime
)
SELECT 
  APPROX_QUANTILES(duration_days, 1000)[SAFE_OFFSET(500)] AS median_duration_days
FROM prescriptions_filtered;