SELECT
  MAX(DATE_DIFF(DATE(prescriptions.stoptime), DATE(prescriptions.starttime), DAY)) AS max_digoxin_prescription_days
FROM
  physionet-data.mimiciv_3_1_hosp.patients AS patients
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions AS admissions
    ON patients.subject_id = admissions.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.prescriptions AS prescriptions
    ON admissions.subject_id = prescriptions.subject_id
    AND admissions.hadm_id = prescriptions.hadm_id
WHERE
  patients.gender = 'M'
  AND patients.anchor_age BETWEEN 82 AND 92
  AND LOWER(prescriptions.drug) LIKE '%digoxin%'
  AND prescriptions.starttime IS NOT NULL
  AND prescriptions.stoptime IS NOT NULL;