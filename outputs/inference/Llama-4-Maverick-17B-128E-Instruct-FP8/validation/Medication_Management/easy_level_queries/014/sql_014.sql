WITH patient_population AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 86 AND 96
),
hospitalized_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM patient_population p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
),
atorvastatin_prescriptions AS (
  SELECT hp.subject_id, hp.hadm_id, 
         p.starttime, p.stoptime,
         CAST(REGEXP_EXTRACT(p.dose_val_rx, r'(\d+(?:\.\d+)?)') AS FLOAT64) AS dose,
         DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM hospitalized_patients hp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON hp.subject_id = p.subject_id AND hp.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%atorvastatin%' 
    AND CAST(REGEXP_EXTRACT(p.dose_val_rx, r'(\d+(?:\.\d+)?)') AS FLOAT64) BETWEEN 40 AND 80
)
SELECT MIN(duration_days) AS min_duration_days
FROM atorvastatin_prescriptions;