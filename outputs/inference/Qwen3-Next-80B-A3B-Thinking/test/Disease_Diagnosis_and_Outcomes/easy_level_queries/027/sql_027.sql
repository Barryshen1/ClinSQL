SELECT MAX(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY)) AS max_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
WHERE diag.seq_num = 1
  AND pat.gender = 'F'
  AND pat.anchor_age BETWEEN 49 AND 59
  AND (
    diag.icd_code LIKE 'K25%' OR
    diag.icd_code LIKE 'K26%' OR
    diag.icd_code LIKE 'K27%' OR
    diag.icd_code LIKE 'K28%' OR
    diag.icd_code = 'K29.0' OR
    diag.icd_code IN ('K92.0', 'K92.1', 'K92.2')
  );