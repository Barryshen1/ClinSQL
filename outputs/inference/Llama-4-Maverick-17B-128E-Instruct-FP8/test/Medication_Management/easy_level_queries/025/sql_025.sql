WITH patient_prescriptions AS (
  SELECT p.subject_id, a.hadm_id, pr.starttime, pr.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON a.hadm_id = pr.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 62 AND 72
  AND LOWER(pr.drug) LIKE '%amiodarone%'
),
single_prescriptions AS (
  SELECT subject_id, hadm_id, starttime, stoptime,
         DATETIME_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM patient_prescriptions pp1
  WHERE NOT EXISTS (
    SELECT 1
    FROM patient_prescriptions pp2
    WHERE pp1.subject_id = pp2.subject_id AND pp1.hadm_id = pp2.hadm_id
    AND pp1.starttime < pp2.stoptime AND pp2.starttime < pp1.stoptime
    AND (pp1.starttime, pp1.stoptime) != (pp2.starttime, pp2.stoptime)
  )
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS Q3,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS IQR
FROM single_prescriptions;