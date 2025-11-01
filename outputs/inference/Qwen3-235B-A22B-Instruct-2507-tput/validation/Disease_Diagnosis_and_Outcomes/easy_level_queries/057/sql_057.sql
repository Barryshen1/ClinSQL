SELECT 
  MIN(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS min_los_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE 
  pat.gender = 'F'
  -- Calculate age at admission
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 88 AND 98
  -- Primary diagnosis only
  AND diag.seq_num = 1
  -- ICD-10 codes for community-acquired pneumonia
  AND diag.icd_version = 10
  AND (
    d_diag.icd_code LIKE 'J18%' OR  -- Pneumonia, unspecified
    d_diag.icd_code LIKE 'J13%' OR  -- Pneumococcal pneumonia
    d_diag.icd_code LIKE 'J14%' OR  -- H. influenzae pneumonia
    d_diag.icd_code LIKE 'J15%' OR  -- Other bacterial pneumonia
    d_diag.icd_code LIKE 'J16%'     -- Pneumonia due to other infectious organisms
  )
  -- Ensure valid admission/discharge times
  AND adm.admittime IS NOT NULL
  AND adm.dischtime IS NOT NULL
  -- Discharge after admission
  AND adm.dischtime >= adm.admittime;