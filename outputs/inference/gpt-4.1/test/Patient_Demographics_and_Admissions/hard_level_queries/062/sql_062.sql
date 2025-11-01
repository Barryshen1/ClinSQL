SELECT COUNT(DISTINCT admissions.hadm_id) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON admissions.hadm_id = diag.hadm_id
WHERE
  patients.gender = 'F'
  AND patients.anchor_age BETWEEN 38 AND 48
  AND LOWER(admissions.insurance) LIKE '%medicare%'
  AND (
    LOWER(admissions.admission_location) LIKE '%emergency%'
    OR LOWER(admissions.admission_location) LIKE '%ed%'
    OR LOWER(admissions.admission_location) LIKE '%er%'
  )
  AND diag.seq_num = 1
  AND (
    -- ICD-10: K81.0 (Acute cholecystitis)
    (diag.icd_version = 10 AND diag.icd_code = 'K81.0')
    -- ICD-9: 5750 (Acute cholecystitis, no decimal in MIMIC-IV ICD-9 codes)
    OR (diag.icd_version = 9 AND diag.icd_code = '5750')
  );