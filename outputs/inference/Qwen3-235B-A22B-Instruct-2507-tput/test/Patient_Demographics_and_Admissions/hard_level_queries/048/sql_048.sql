SELECT COUNT(*) AS cohort_count
FROM (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F'
    AND diag.seq_num = 1  -- principal diagnosis
    AND diag.icd_version = 10
    AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%emergency%'
    -- Calculate age at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89
) AS subquery;