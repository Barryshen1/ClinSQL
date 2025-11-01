SELECT APPROX_QUANTILES(icustays.los, 1)[OFFSET(0)] AS median_icu_los
FROM physionet-data.mimiciv_3_1_hosp.patients AS patients
JOIN physionet-data.mimiciv_3_1_hosp.admissions AS admissions
  ON patients.subject_id = admissions.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS diagnoses_icd
  ON admissions.hadm_id = diagnoses_icd.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d_icd_diagnoses
  ON diagnoses_icd.icd_code = d_icd_diagnoses.icd_code
  AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
JOIN physionet-data.mimiciv_3_1_icu.icustays AS icustays
  ON admissions.hadm_id = icustays.hadm_id
WHERE patients.gender = 'F'
  AND patients.anchor_age BETWEEN 58 AND 68
  AND (LOWER(d_icd_diagnoses.long_title) LIKE '%sepsis%'
       OR LOWER(d_icd_diagnoses.long_title) LIKE '%septicemia%');