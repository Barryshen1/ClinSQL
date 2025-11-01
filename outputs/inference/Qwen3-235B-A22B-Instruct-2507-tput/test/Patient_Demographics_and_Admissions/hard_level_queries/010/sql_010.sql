SELECT COUNT(*) AS admission_count
FROM (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.gender,
    a.admittime,
    a.admission_location,
    a.insurance,
    d_icd.icd_code,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_order
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND a.admission_location = 'Emergency Department'
    AND a.insurance = 'Medicare'
    AND diag.seq_num = 1  -- Principal diagnosis
    AND diag.icd_version = 10
    AND d_icd.icd_code LIKE 'E1_.1%'  -- Covers E10.1, E11.1, E13.1, etc.
) sub
WHERE age_at_admission BETWEEN 43 AND 53
  AND admission_order = 1;