SELECT 
  MAX(DATE_DIFF(dischtime, admittime, DAY)) AS max_hospital_los_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pat 
  ON adm.subject_id = pat.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
  ON adm.subject_id = diag.subject_id 
  AND adm.hadm_id = diag.hadm_id
WHERE 
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 84 AND 94
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 
     AND (
       diag.icd_code LIKE '433%1' 
       OR diag.icd_code LIKE '434%1' 
       OR diag.icd_code = '436'
     ))
    OR 
    (diag.icd_version = 10 
     AND diag.icd_code LIKE 'I63%'
    )
  );