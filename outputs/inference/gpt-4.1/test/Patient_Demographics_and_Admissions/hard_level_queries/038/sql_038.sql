SELECT COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 90 AND 100
  AND adm.insurance = 'Medicare'
  AND (
    LOWER(adm.admission_location) LIKE '%transfer%'
    OR LOWER(adm.admission_location) LIKE '%hosp%'
    OR LOWER(adm.admission_location) LIKE '%extram%'
  )
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '5856')
    OR (diag.icd_version = 10 AND diag.icd_code = 'N186')
  );