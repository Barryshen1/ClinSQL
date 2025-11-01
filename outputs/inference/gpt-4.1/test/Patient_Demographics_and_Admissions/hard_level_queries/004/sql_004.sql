SELECT COUNT(DISTINCT adm.hadm_id) AS num_index_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS diag
  ON adm.hadm_id = diag.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS dicd
  ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 85 AND 95
  AND LOWER(adm.insurance) LIKE '%medicare%'
  AND (
    LOWER(adm.admission_location) LIKE '%transfer from hospital%'
    OR LOWER(adm.admission_location) LIKE '%transfer from another hospital%'
  )
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code LIKE '730%')
    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'M86%')
  );