WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 73 AND 83
),
admission_filter AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IS NOT NULL
),
nitrate_prescriptions AS (
  SELECT p.subject_id, p.hadm_id, p.drug, DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN patient_filter pf ON p.subject_id = pf.subject_id
  INNER JOIN admission_filter af ON p.hadm_id = af.hadm_id
  WHERE LOWER(p.drug) LIKE '%nitroglycerin%' OR LOWER(p.drug) LIKE '%nitrate%'
)

SELECT 
  STDDEV(duration_days) AS sd_duration_days
FROM 
  nitrate_prescriptions;