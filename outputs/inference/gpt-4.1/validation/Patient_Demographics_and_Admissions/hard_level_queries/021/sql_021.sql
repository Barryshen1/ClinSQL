SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  -- Female
  p.gender = 'F'
  -- Medicare insurance
  AND a.insurance = 'Medicare'
  -- Age at admission between 82 and 92
  AND (
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    BETWEEN 82 AND 92
  )
  -- Admitted from ED
  AND LOWER(a.admission_location) LIKE '%emergency%'
  -- Principal diagnosis only
  AND d.seq_num = 1
  -- Acute pancreatitis ICD-9 or ICD-10
  AND (
    (d.icd_version = 9 AND d.icd_code = '5770')
    OR
    (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
  )
  -- Discharged (not still admitted)
  AND a.dischtime IS NOT NULL;