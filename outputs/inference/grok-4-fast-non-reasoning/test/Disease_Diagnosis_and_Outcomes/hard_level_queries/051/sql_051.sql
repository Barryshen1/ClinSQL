WITH cohort AS (
  -- Base cohort: male, 35-45, inpatient admissions with acute pancreatitis (primary dx)
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1  -- Primary diagnosis
  WHERE 
    CAST(p.gender AS STRING) = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND (
      -- Acute pancreatitis ICD-10: K85.*
      (d.icd_version = '10' AND REGEXP_CONTAINS(d.icd_code, r'^K85'))
      OR
      -- Acute pancreatitis ICD-9: 577.0
      (d.icd_version = '9' AND d.icd_code = '577.0')
    )
),

-- Compute risk score components per admission
risk_scores AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    -- Diagnosis count (all dx, including pancreatitis)
    COUNT(icd.icd_code) AS dx_count,
    -- Major complication flags (binary, then sum)
    MAX(CASE 
      WHEN (
        (icd.icd_version = '10' AND REGEXP_CONTAINS(icd.icd_code, r'^N17'))
        OR (icd.icd_version = '9' AND REGEXP_CONTAINS(icd.icd_code, r'^584'))
      ) THEN 1 ELSE 0 
    END) AS flag_aki,
    MAX(CASE 
      WHEN (
        (icd.icd_version = '10' AND REGEXP_CONTAINS(icd.icd_code, r'^A41'))
        OR (icd.icd_version = '9' AND (REGEXP_CONTAINS(icd.icd_code, r'^038') OR icd.icd_code IN ('99591', '99592')))
      ) THEN 1 ELSE 0 
    END) AS flag_sepsis,
    MAX(CASE 
      WHEN (
        (icd.icd_version = '10' AND REGEXP_CONTAINS(icd.icd_code, r'^J96'))
        OR (icd.icd_version = '9' AND icd.icd_code IN ('51881', '51882', '7991'))
      ) THEN 1 ELSE 0 
    END) AS flag_resp_failure,
    MAX(CASE 
      WHEN (
        (icd.icd_version = '10' AND REGEXP_CONTAINS(icd.icd_code, r'^I21'))
        OR (icd.icd_version = '9' AND REGEXP_CONTAINS(icd.icd_code, r'^410'))
      ) THEN 1 ELSE 0 
    END) AS flag_ami,
    MAX(CASE 
      WHEN (
        (icd.icd_version = '10' AND REGEXP_CONTAINS(icd.icd_code, r'^K92[0-2]'))
        OR (icd.icd_version = '9' AND REGEXP_CONTAINS(icd.icd_code, r'^578'))
      ) THEN 1 ELSE 0 
    END) AS flag_gi_bleed
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd
    ON c.hadm_id = icd.hadm_id  -- All diagnoses for flags/count
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

-- Add risk score, LOS, and quartiles
metrics AS (
  SELECT 
    *,
    -- Risk score: dx_count + 5 * sum of flags
    dx_count + 5 * (flag_aki + flag_sepsis + flag_resp_failure + flag_ami + flag_gi_bleed) AS risk_score,
    -- Total flags for major comp rate
    (flag_aki + flag_sepsis + flag_resp_failure + flag_ami + flag_gi_bleed) AS total_flags,
    -- LOS in days
    DATE_DIFF(DATETIME(dischtime), DATETIME(admittime), DAY) AS los_days,
    NTILE(4) OVER (ORDER BY dx_count + 5 * (flag_aki + flag_sepsis + flag_resp_failure + flag_ami + flag_gi_bleed)) AS quartile
  FROM risk_scores
),

-- Aggregate by quartiles and overall
overall AS (
  SELECT 
    'Overall' AS group_level,
    NULL AS quartile,
    COUNT(*) AS n_admissions,
    ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS mortality_rate_pct,
    ROUND(AVG(total_flags) / 5.0 * 100, 2) AS major_comp_rate_pct,
    PERCENTILE_CONT(los_days, 0.5) IGNORE NULLS AS median_los_days
  FROM metrics
  WHERE hospital_expire_flag = 0 OR los_days IS NOT NULL  -- Include all for counts/rates, survivors for LOS
),

quartiles AS (
  SELECT 
    'Quartile' AS group_level,
    CAST(quartile AS STRING) AS quartile,
    COUNT(*) AS n_admissions,
    ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS mortality_rate_pct,
    ROUND(AVG(total_flags) / 5.0 * 100, 2) AS major_comp_rate_pct,
    PERCENTILE_CONT(los_days, 0.5) IGNORE NULLS AS median_los_days
  FROM metrics
  GROUP BY quartile
)

SELECT * FROM overall
UNION ALL
SELECT * FROM quartiles
ORDER BY CAST(quartile AS INT64);