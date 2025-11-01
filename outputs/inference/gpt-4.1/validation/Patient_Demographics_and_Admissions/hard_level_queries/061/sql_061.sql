SELECT COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
  ON adm.hadm_id = dx.hadm_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 63 AND 73
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'TRANSFER FROM HOSP/EXTRAM'
  AND dx.seq_num = 1
  AND (
    -- ICD-10 atrial fibrillation codes
    (dx.icd_version = 10 AND (
      dx.icd_code = 'I48' OR
      dx.icd_code LIKE 'I480%' OR
      dx.icd_code LIKE 'I481%' OR
      dx.icd_code LIKE 'I482%' OR
      dx.icd_code LIKE 'I483%' OR
      dx.icd_code LIKE 'I484%' OR
      dx.icd_code LIKE 'I485%' OR
      dx.icd_code LIKE 'I486%' OR
      dx.icd_code LIKE 'I487%' OR
      dx.icd_code LIKE 'I488%' OR
      dx.icd_code LIKE 'I489%'
    ))
    OR
    -- ICD-9 atrial fibrillation code
    (dx.icd_version = 9 AND dx.icd_code = '42731')
  );