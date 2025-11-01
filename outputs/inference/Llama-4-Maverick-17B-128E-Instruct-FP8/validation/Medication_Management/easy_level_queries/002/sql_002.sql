WITH patient_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 59 AND 69
),
amiodarone_prescriptions AS (
  SELECT p.subject_id, p.hadm_id, p.starttime, p.stoptime,
         DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN patient_cohort pc ON p.subject_id = pc.subject_id
  WHERE LOWER(p.drug) LIKE '%amiodarone%'
  AND p.starttime IS NOT NULL AND p.stoptime IS NOT NULL
),
single_prescriptions AS (
  SELECT hadm_id, duration_days
  FROM amiodarone_prescriptions
  WHERE hadm_id IN (
    SELECT hadm_id
    FROM amiodarone_prescriptions
    GROUP BY hadm_id
    HAVING COUNT(*) = 1
  )
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS q3
FROM single_prescriptions;