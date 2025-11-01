SELECT COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pat.subject_id = adm.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id AND diag.seq_num = 1
WHERE
  pat.gender = 'F'
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'EMERGENCY ROOM ADMIT'
  AND adm.dischtime IS NOT NULL
  AND (
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)
  ) BETWEEN 68 AND 78
  AND (
    (diag.icd_version = 9 AND diag.icd_code >= '430' AND diag.icd_code < '433')
    OR
    (diag.icd_version = 10 AND (
      diag.icd_code LIKE 'I60%' 
      OR diag.icd_code LIKE 'I61%' 
      OR diag.icd_code LIKE 'I62%'
    ))
  );