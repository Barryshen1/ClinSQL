WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 57 AND 67
),
antiplatelet_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    CASE WHEN LOWER(drug) LIKE '%aspirin%' THEN 1 ELSE 0 END AS has_aspirin,
    CASE WHEN LOWER(drug) LIKE '%clopidogrel%' OR
             LOWER(drug) LIKE '%ticagrelor%' OR
             LOWER(drug) LIKE '%prasugrel%' THEN 1 ELSE 0 END AS has_p2y12
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    (LOWER(drug) LIKE '%aspirin%' OR
     LOWER(drug) LIKE '%clopidogrel%' OR
     LOWER(drug) LIKE '%ticagrelor%' OR
     LOWER(drug) LIKE '%prasugrel%')
    AND stoptime IS NOT NULL
),
dapt_admissions AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MIN(ap.starttime) AS first_start,
    MAX(ap.stoptime) AS last_stop
  FROM cohort c
  INNER JOIN antiplatelet_prescriptions ap
    ON c.subject_id = ap.subject_id AND c.hadm_id = ap.hadm_id
  GROUP BY c.subject_id, c.hadm_id
  HAVING 
    MAX(has_aspirin) = 1
    AND MAX(has_p2y12) = 1
    AND MAX(ap.stoptime) >= MIN(ap.starttime)  -- Ensure valid duration
),
durations AS (
  SELECT
    TIMESTAMP_DIFF(last_stop, first_start, DAY) AS dapt_duration_days
  FROM dapt_admissions
)
SELECT
  APPROX_QUANTILES(dapt_duration_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(dapt_duration_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(dapt_duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(dapt_duration_days, 4)[OFFSET(1)] AS iqr
FROM durations
LIMIT 1;