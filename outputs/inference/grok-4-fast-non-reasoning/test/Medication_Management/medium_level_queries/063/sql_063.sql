WITH cohort AS (
  -- Base cohort: males 45-55 with diabetes and heart failure (both diagnoses present)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id 
    AND a.hadm_id = SAFE_CAST(d.hadm_id AS INT64)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime  -- Exclude zero-length stays
    AND d.icd_version = '10'
    GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime
    HAVING SUM(CASE WHEN d.icd_code LIKE 'E1[0-8]%' THEN 1 ELSE 0 END) > 0  -- Has diabetes
       AND SUM(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) > 0      -- Has heart failure
),

orders AS (
  -- Antidiabetic orders with timing (insulin vs oral antidiabetics)
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    CAST(pr.starttime AS TIMESTAMP) AS starttime,
    pr.drug,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%'
        OR LOWER(pr.drug) LIKE '%sulfonylurea%'
        OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%'
        OR LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%'
        OR LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%dpp4%'
        OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%sglt2%'
        OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%glp1%'
        OR LOWER(pr.drug) LIKE '%acarbose%' OR LOWER(pr.drug) LIKE '%miglitol%'
      THEN 'oral'
      ELSE NULL 
    END AS drug_type
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND c.hadm_id = SAFE_CAST(pr.hadm_id AS INT64)
  WHERE pr.drug_type IS NOT NULL  -- Only antidiabetics
),

flags AS (
  -- Binary flags for initiation in each window per admission
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    -- First 12h: any insulin?
    MAX(CASE WHEN drug_type = 'insulin' 
             AND starttime >= admittime 
             AND starttime <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS insulin_first,
    -- First 12h: any oral?
    MAX(CASE WHEN drug_type = 'oral' 
             AND starttime >= admittime 
             AND starttime <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS oral_first,
    -- Final 72h: any insulin?
    MAX(CASE WHEN drug_type = 'insulin' 
             AND starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR)
             AND starttime <= dischtime
             THEN 1 ELSE 0 END) AS insulin_final,
    -- Final 72h: any oral?
    MAX(CASE WHEN drug_type = 'oral' 
             AND starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR)
             AND starttime <= dischtime
             THEN 1 ELSE 0 END) AS oral_final
  FROM orders
  GROUP BY hadm_id, admittime, dischtime
),

totals AS (
  -- Aggregate rates
  SELECT 
    COUNT(*) AS total_adms,
    SUM(insulin_first) AS insulin_first_count,
    SUM(oral_first) AS oral_first_count,
    SUM(insulin_final) AS insulin_final_count,
    SUM(oral_final) AS oral_final_count
  FROM flags
)

-- Final rates and pp differences
SELECT 
  total_adms,
  -- First 12h rates
  ROUND((insulin_first_count * 100.0 / total_adms), 2) AS insulin_first_rate_pct,
  ROUND((oral_first_count * 100.0 / total_adms), 2) AS oral_first_rate_pct,
  -- Final 72h rates
  ROUND((insulin_final_count * 100.0 / total_adms), 2) AS insulin_final_rate_pct,
  ROUND((oral_final_count * 100.0 / total_adms), 2) AS oral_final_rate_pct,
  -- PP differences (first - final)
  ROUND((insulin_first_count * 100.0 / total_adms) - (insulin_final_count * 100.0 / total_adms), 2) AS insulin_pp_diff,
  ROUND((oral_first_count * 100.0 / total_adms) - (oral_final_count * 100.0 / total_adms), 2) AS oral_pp_diff
FROM totals;