SELECT COUNT(DISTINCT adm.hadm_id) AS num_index_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
  ON adm.hadm_id = dx.hadm_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 36 AND 46
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'TRANSFER FROM ANOTHER HOSPITAL'
  AND dx.seq_num = 1
  AND (
    -- ICD-10 hemorrhagic stroke
    (dx.icd_version = 10 AND (
      REGEXP_CONTAINS(dx.icd_code, r'^I60') OR
      REGEXP_CONTAINS(dx.icd_code, r'^I61') OR
      REGEXP_CONTAINS(dx.icd_code, r'^I62')
    ))
    OR
    -- ICD-9 hemorrhagic stroke
    (dx.icd_version = 9 AND (
      dx.icd_code = '430' OR
      dx.icd_code = '431' OR
      REGEXP_CONTAINS(dx.icd_code, r'^432')
    ))
  );