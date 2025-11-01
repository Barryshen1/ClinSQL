WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
),
prescription_durations AS (
  SELECT 
    pr.subject_id,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN eligible_patients ep
    ON pr.subject_id = ep.subject_id
  WHERE LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
),
filtered_durations AS (
  SELECT *
  FROM prescription_durations
  WHERE duration_days >= 0
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS iqr_q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_days) AS iqr_q3,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_days) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS iqr_range
FROM filtered_durations
WHERE duration_days IS NOT NULL;