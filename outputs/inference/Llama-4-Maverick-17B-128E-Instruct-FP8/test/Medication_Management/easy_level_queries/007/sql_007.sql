WITH patient_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 90 AND 100
),
admissions_cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_cohort p ON a.subject_id = p.subject_id
),
thiazide_like_prescriptions AS (
  SELECT p.hadm_id, DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE p.hadm_id IN (SELECT hadm_id FROM admissions_cohort)
  AND (LOWER(p.drug) LIKE '%thiazide%' OR LOWER(p.drug) LIKE '%metolazone%')
),
durations AS (
  SELECT duration_days
  FROM thiazide_like_prescriptions
  WHERE duration_days IS NOT NULL AND duration_days >= 0
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS iqr_days
FROM durations;