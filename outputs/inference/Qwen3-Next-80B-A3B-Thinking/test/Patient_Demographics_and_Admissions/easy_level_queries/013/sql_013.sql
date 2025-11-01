SELECT MAX(TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY)) AS max_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
WHERE patients.gender = 'M'
  AND patients.anchor_age BETWEEN 58 AND 68
  AND admissions.dischtime IS NOT NULL;