WITH 
-- Identify MCS procedures
mcs_procedures AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    icd_version = 'ICD-9' 
    AND icd_code IN (
      '37.31', '37.32', '37.33', '37.34', '37.35', '37.36', 
      '37.41', '37.42', '37.43', '37.44', '37.45', '37.46', 
      '37.51', '37.52', '37.53', '37.54', '37.55', '37.56'
    )
  UNION ALL
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    icd_version = 'ICD-10' 
    AND icd_code IN (
      '5A021', '5A022', '5A023', '5A024', '5A025', '5A026', 
      '5A027', '5A028', '5A029', '5A02A', '5A02B', '5A02C', 
      '5A02D', '5A02E', '5A02F', '5A02G', '5A02H', '5A02J', 
      '5A02K'
    )
),
-- Filter patients
patients_filter AS (
  SELECT 
    subject_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE 
    gender = 'M' 
    AND anchor_age BETWEEN 56 AND 66
)

SELECT 
  STDDEV(mcs_count) AS std_dev_mcs_procedures
FROM (
  SELECT 
    p.subject_id, 
    COUNT(DISTINCT mcs.hadm_id) AS mcs_count
  FROM 
    patients_filter p
  LEFT JOIN 
    mcs_procedures mcs ON p.subject_id = mcs.subject_id
  GROUP BY 
    p.subject_id
) AS patient_mcs_counts;