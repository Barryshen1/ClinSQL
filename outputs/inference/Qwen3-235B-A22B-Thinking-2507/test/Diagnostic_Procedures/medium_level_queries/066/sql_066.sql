WITH patients_asthma AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    -- Compute age at admission more accurately
    TIMESTAMP_DIFF(a.admittime, MAKE_TIMESTAMP(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_at_admission,
    -- Compute LOS in days (more accurately)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id
  WHERE 
    p.gender = 'F'
    AND (
      (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '493%')
      OR (d_icd.icd_version = 10 AND (d_icd.icd_code LIKE 'J45%' OR d_icd.icd_code = 'J46'))
    )
),
cohort AS (
  SELECT 
    pa.hadm_id,
    pa.los_days
  FROM patients_asthma pa
  WHERE 
    pa.age_at_admission BETWEEN 88 AND 98
    AND pa.los_days > 0  -- Exclude same-day admissions
    AND pa.los_days <= 7  -- Only include stays up to 7 days
),
diagnostic_procedures AS (
  -- Get diagnostic procedures from procedures_icd
  SELECT 
    pic.hadm_id,
    pic.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pic
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_ip
    ON pic.icd_code = d_ip.icd_code AND pic.icd_version = d_ip.icd_version
  WHERE 
    LOWER(d_ip.long_title) LIKE '%diagnostic%' 
    OR LOWER(d_ip.long_title) LIKE '%diagnosis%'
    OR LOWER(d_ip.long_title) LIKE '%exam%'
    OR LOWER(d_ip.long_title) LIKE '%imaging%'
    OR LOWER(d_ip.long_title) LIKE '%scan%'
    OR LOWER(d_ip.long_title) LIKE '%test%'
  
  UNION ALL
  
  -- Get diagnostic procedures from hcpcsevents
  SELECT 
    hce.hadm_id,
    hce.hcpcs_cd AS icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hce
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d_h
    ON hce.hcpcs_cd = d_h.code
  WHERE 
    LOWER(d_h.long_description) LIKE '%diagnostic%' 
    OR LOWER(d_h.long_description) LIKE '%diagnosis%'
    OR LOWER(d_h.long_description) LIKE '%exam%'
    OR LOWER(d_h.long_description) LIKE '%imaging%'
    OR LOWER(d_h.long_description) LIKE '%scan%'
    OR LOWER(d_h.long_description) LIKE '%test%'
),
procedures_count AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_diagnostic_procedures
  FROM diagnostic_procedures
  GROUP BY hadm_id
),
admissions_with_procedures AS (
  SELECT 
    c.hadm_id,
    c.los_days,
    COALESCE(pc.num_diagnostic_procedures, 0) AS num_diagnostic_procedures
  FROM cohort c
  LEFT JOIN procedures_count pc
    ON c.hadm_id = pc.hadm_id
)
SELECT 
  CASE 
    WHEN los_days <= 3 THEN '1-3'
    ELSE '4-7'
  END AS los_group,
  APPROX_QUANTILES(num_diagnostic_procedures, 1000 IGNORE NULLS)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(num_diagnostic_procedures, 1000 IGNORE NULLS)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(num_diagnostic_procedures, 1000 IGNORE NULLS)[OFFSET(750)] AS p75
FROM admissions_with_procedures
WHERE los_days <= 7  -- Ensure we only include stays up to 7 days
GROUP BY los_group
ORDER BY los_group;