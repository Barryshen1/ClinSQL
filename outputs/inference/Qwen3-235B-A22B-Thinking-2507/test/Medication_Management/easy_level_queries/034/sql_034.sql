SELECT 
  MAX(
    (UNIX_SECONDS(CAST(prescriptions.stoptime AS TIMESTAMP)) - UNIX_SECONDS(CAST(prescriptions.starttime AS TIMESTAMP))) / 86400.0
  ) AS longest_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.patients` AS patients
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
  ON patients.subject_id = admissions.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS prescriptions
  ON admissions.hadm_id = prescriptions.hadm_id
  AND admissions.subject_id = prescriptions.subject_id
WHERE 
  patients.gender = 'F'
  AND (
    patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)
  ) BETWEEN 51 AND 61
  AND (
    LOWER(prescriptions.drug) LIKE '%hydralazine%'
    OR (
      LOWER(prescriptions.drug) LIKE '%isosorbide%' 
      AND LOWER(prescriptions.drug) LIKE '%dinitrate%'
    )
  )
  AND prescriptions.starttime IS NOT NULL
  AND prescriptions.stoptime IS NOT NULL
  AND prescriptions.stoptime >= prescriptions.starttime;