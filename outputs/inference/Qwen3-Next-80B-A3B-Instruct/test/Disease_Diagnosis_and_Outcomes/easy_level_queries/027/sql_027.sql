SELECT MAX(TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY)) AS max_length_of_stay_days
FROM physionet-data.mimiciv_3_1_hosp.patients AS patients
JOIN physionet-data.mimiciv_3_1_hosp.admissions AS admissions
  ON patients.subject_id = admissions.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS diagnoses_icd
  ON admissions.hadm_id = diagnoses_icd.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d_icd_diagnoses
  ON diagnoses_icd.icd_code = d_icd_diagnoses.icd_code
  AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
WHERE patients.gender = 'F'
  AND patients.anchor_age BETWEEN 49 AND 59
  AND diagnoses_icd.seq_num = 1
  AND d_icd_diagnoses.long_title LIKE '%upper gastrointestinal hemorrhage%';