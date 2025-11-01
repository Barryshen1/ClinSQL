WITH cohort AS (
  -- Base cohort: men 51-61 with AMI admission (ICD-10)
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    -- Determine AMI type from diagnoses (prioritize primary, but check all)
    CASE 
      WHEN STRING_AGG(d.icd_code, ',' ORDER BY d.seq_num) LIKE '%I21.[0-3]%' 
      THEN 'STEMI'  -- I21.0-I21.3: STEMI by infarction site
      WHEN STRING_AGG(d.icd_code, ',' ORDER BY d.seq_num) LIKE '%I21.A1%' 
           OR STRING_AGG(d.icd_code, ',' ORDER BY d.seq_num) LIKE '%I21.4%' 
      THEN 'NSTEMI'  -- I21.A1: MI type 2; I21.4: acute MI unspecified (often NSTEMI)
      ELSE NULL 
    END AS ami_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.icd_version = 10  -- Fix: INT64 comparison
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (d.icd_code LIKE 'I21.%'  -- Any AMI code
         OR d.icd_code LIKE 'I21.A%' 
         OR d.icd_code = 'I21.4')
    AND a.dischtime IS NOT NULL  -- Exclude ongoing
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0  -- LOS > 0
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.admission_type
  HAVING ami_type IS NOT NULL  -- Only clear STEMI/NSTEMI
),
comorbidities AS (
  -- Add comorbidity flags per admission
  SELECT 
    c.*,
    -- CKD: any N18* code
    MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    -- Diabetes: E10*-E13* (exclude E13.1x gestational if needed, but simplify)
    MAX(CASE WHEN d.icd_code LIKE 'E1[0-3]%' THEN 1 ELSE 0 END) AS has_diabetes,
    -- Comorbidity count (CKD + diabetes only, per question focus)
    (MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) +
     MAX(CASE WHEN d.icd_code LIKE 'E1[0-3]%' THEN 1 ELSE 0 END)) AS comorb_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.hadm_id = d.hadm_id AND d.icd_version = 10  -- Fix: INT64 comparison
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, 
    c.admission_type, c.ami_type
),
los_comorb AS (
  -- Compute LOS and group
  SELECT 
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM comorbidities
),
grouped AS (
  -- Group LOS and comorbidities
  SELECT 
    ami_type,
    CASE 
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
      ELSE '>=10'
    END AS los_group,
    CASE 
      WHEN comorb_count BETWEEN 0 AND 1 THEN '0-1'
      WHEN comorb_count = 2 THEN '2'
      ELSE '>=3'
    END AS comorb_group,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS n_deaths,
    AVG(CAST(has_ckd AS FLOAT64)) * 100 AS pct_ckd,
    AVG(CAST(has_diabetes AS FLOAT64)) * 100 AS pct_diabetes
  FROM los_comorb
  GROUP BY ami_type, los_group, comorb_group
)
-- Final output: mortality % and N, with prevalences
SELECT 
  ami_type,
  los_group,
  comorb_group,
  n,
  ROUND((n_deaths * 100.0 / n), 1) AS mortality_pct,
  ROUND(pct_ckd, 1) AS ckd_prevalence_pct,
  ROUND(pct_diabetes, 1) AS diabetes_prevalence_pct
FROM grouped
ORDER BY ami_type, los_group, comorb_group;