WITH amio_prescriptions AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),
single_amio_per_hadm AS (
  SELECT 
    hadm_id
  FROM amio_prescriptions
  GROUP BY hadm_id
  HAVING COUNT(*) = 1
),
durations AS (
  SELECT a.duration_days
  FROM amio_prescriptions a
  JOIN single_amio_per_hadm s
    ON a.hadm_id = s.hadm_id
)
SELECT 
  q[2] - q[0] AS iqr_days,  -- Q3 - Q1
  q[0] AS q1_days,
  q[1] AS median_days,
  q[2] AS q3_days
FROM (
  SELECT APPROX_QUANTILES(duration_days, 4) AS q
  FROM durations
);