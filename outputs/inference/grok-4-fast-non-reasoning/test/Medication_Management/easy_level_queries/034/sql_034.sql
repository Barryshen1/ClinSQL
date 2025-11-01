SELECT 
  MAX(DATE_DIFF(DATE(prescriptions.stoptime), DATE(prescriptions.starttime), DAY)) AS max_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` patients
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` prescriptions
  ON patients.subject_id = prescriptions.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` admissions
  ON prescriptions.hadm_id = admissions.hadm_id
WHERE 
  patients.gender = 'F'
  AND patients.anchor_age BETWEEN 51 AND 61
  AND (LOWER(prescriptions.drug) LIKE '%hydralazine%' 
       OR LOWER(prescriptions.drug) LIKE '%isosorbide dinitrate%')
  AND prescriptions.stoptime IS NOT NULL
  AND DATE(prescriptions.stoptime) > DATE(prescriptions.starttime);