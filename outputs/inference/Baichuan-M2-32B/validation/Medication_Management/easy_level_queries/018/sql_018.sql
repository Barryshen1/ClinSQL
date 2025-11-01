WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.admittime, TIMESTAMP(DATE(p.anchor_year - p.anchor_age, 1, 1)), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND TIMESTAMP_DIFF(a.admittime, TIMESTAMP(DATE(p.anchor_year - p.anchor_age, 1, 1)), YEAR) BETWEEN 82 AND 92
),
prescriptions_with_duration AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    p.starttime,
    p.stoptime,
    COALESCE(p.stoptime, c.dischtime) AS end_time,
    DATEDIFF(CAST(COALESCE(p.stoptime, c.dischtime) AS DATE), CAST(p.starttime AS DATE)) AS duration_days
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%digoxin%'
    AND p.starttime BETWEEN c.admittime AND c.dischtime
    AND COALESCE(p.stoptime, c.dischtime) >= p.starttime
    AND p.starttime IS NOT NULL
)
SELECT MAX(duration_days) AS longest_duration
FROM prescriptions_with_duration;