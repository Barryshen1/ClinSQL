SELECT COUNT(DISTINCT admissions.hadm_id) AS num_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses
  ON admissions.hadm_id = diagnoses.hadm_id
WHERE
  -- Female
  patients.gender = 'F'
  -- Age at admission between 68 and 78
  AND patients.anchor_age BETWEEN 68 AND 78
  -- Medicare insurance
  AND LOWER(admissions.insurance) LIKE '%medicare%'
  -- Admitted from ED
  AND LOWER(admissions.admission_location) LIKE '%emergency%'
  -- Documented discharge (not expired in hospital)
  AND admissions.dischtime IS NOT NULL
  AND admissions.hospital_expire_flag = 0
  -- Principal diagnosis
  AND diagnoses.seq_num = 1
  -- Hemorrhagic stroke ICD-9/10 codes
  AND (
    -- ICD-9
    (diagnoses.icd_version = 9 AND (
      diagnoses.icd_code LIKE '430%' OR
      diagnoses.icd_code LIKE '431%' OR
      diagnoses.icd_code LIKE '432%'
    ))
    -- ICD-10
    OR
    (diagnoses.icd_version = 10 AND (
      diagnoses.icd_code LIKE 'I60%' OR
      diagnoses.icd_code LIKE 'I61%' OR
      diagnoses.icd_code LIKE 'I62%'
    ))
  );