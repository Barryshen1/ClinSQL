SELECT 
  COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` pat
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pat.subject_id = adm.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
WHERE 
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 43 AND 53
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND diag.seq_num = 1
  AND diag.icd_version = '10'
  AND diag.icd_code IN ('E10.10', 'E13.10', 'E14.10');