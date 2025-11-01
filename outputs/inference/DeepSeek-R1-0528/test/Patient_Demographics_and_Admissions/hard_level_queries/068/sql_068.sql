SELECT COUNT(DISTINCT admissions.hadm_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses
  ON admissions.hadm_id = diagnoses.hadm_id
  AND diagnoses.seq_num = 1  -- Principal diagnosis
WHERE
  -- Admission from SNF (exact values)
  admissions.admission_location IN (
    'TRANSFER FROM SKILLED NURSING FACILITY (SNF)',
    'TRANSFER FROM SNF'
  )
  AND admissions.insurance = 'Medicare'
  AND patients.gender = 'M'
  -- Age 43-53 at admission
  AND (
    patients.anchor_age + 
    (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)
  ) BETWEEN 43 AND 53
  -- Dehydration ICD codes (ICD-9 and ICD-10)
  AND (
    (diagnoses.icd_version = 9 AND diagnoses.icd_code IN ('276.5', '276.50', '276.51', '276.52'))
    OR
    (diagnoses.icd_version = 10 AND diagnoses.icd_code IN ('E86.0', 'E86.1', 'E86.9'))
  );