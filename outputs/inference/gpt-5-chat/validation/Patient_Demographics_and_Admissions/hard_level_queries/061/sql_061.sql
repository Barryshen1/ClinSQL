SELECT COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.subject_id = diag.subject_id
  AND adm.hadm_id = diag.hadm_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 63 AND 73
  AND adm.insurance = 'Medicare'
  AND LOWER(adm.admission_location) LIKE 'transfer from hospital%'
  AND diag.seq_num = 1
  AND (
        (diag.icd_version = 9 AND diag.icd_code = '42731')  -- ICD-9-CM: Atrial fibrillation
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I48%') -- ICD-10-CM: Atrial fibrillation family
      );