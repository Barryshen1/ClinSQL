SELECT COUNT(DISTINCT adm.hadm_id) AS num_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 46 AND 56
  AND LOWER(adm.insurance) LIKE '%medicare%'
  AND (
    LOWER(adm.admission_location) LIKE '%hospital%'
    OR LOWER(adm.admission_location) LIKE '%hosp%'
  )
  AND diag.seq_num = 1
  AND (
    -- ICD-9 hip fracture: 820.xx
    (diag.icd_version = 9 AND diag.icd_code LIKE '820%')
    -- ICD-10 hip fracture: S72.0xx, S72.1xx, S72.2xx
    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'S72%')
  );