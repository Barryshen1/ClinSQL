WITH cohort AS (
  -- Base cohort: males aged 46-56 with AMI
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    d.seq_num,
    d.icd_code,
    d.icd_version
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND a.hadm_id IS NOT NULL
    AND (
      -- ICD-9 AMI
      (d.icd_version = '9' AND d.icd_code LIKE '410%')
      OR
      -- ICD-10 AMI
      (d.icd_version = '10' AND d.icd_code LIKE 'I21%')
    )
),

complications AS (
  -- Flag and count major complications per admission
  SELECT 
    c.hadm_id,
    MAX(c.anchor_age) AS anchor_age,
    MIN(c.admittime) AS admittime,
    MAX(c.dischtime) AS dischtime,
    MAX(c.hospital_expire_flag) AS hospital_expire_flag,
    -- Count major complications from diagnoses (secondary)
    COUNT(DISTINCT 
      CASE 
        WHEN c.icd_version = '9' 
             AND c.seq_num > 1
             AND (c.icd_code = '785.51' OR c.icd_code = '427.41' OR c.icd_code = '427.5' OR c.icd_code = '998.11')
             THEN CONCAT('diag9_', c.icd_code)
        WHEN c.icd_version = '10' 
             AND c.seq_num > 1
             AND (c.icd_code = 'I50.1' OR c.icd_code = 'I48' OR c.icd_code = 'I46' OR c.icd_code LIKE 'T81.0%')
             THEN CONCAT('diag10_', c.icd_code)
        ELSE NULL 
      END
    ) AS major_comp_count
  FROM cohort c
  GROUP BY c.hadm_id
),

risk_strat AS (
  SELECT 
    *,
    anchor_age + COALESCE(major_comp_count, 0) AS composite_score,
    CASE WHEN COALESCE(major_comp_count, 0) >= 1 THEN 1 ELSE 0 END AS has_major_comp,
    SAFE.DATE_DIFF(PARSE_DATE('%Y-%m-%d %H:%M:%S', dischtime), PARSE_DATE('%Y-%m-%d %H:%M:%S', admittime), DAY) AS los_days
  FROM complications
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM risk_strat
),

survivor_los AS (
  SELECT 
    quintile,
    PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY quintile) AS median_los_days
  FROM quintiles
  WHERE hospital_expire_flag = 0
)

-- Aggregate outcomes by quintile
SELECT 
  q.quintile,
  ROUND(AVG(q.hospital_expire_flag) * 100.0, 2) AS mortality_pct,
  ROUND(AVG(q.has_major_comp) * 100.0, 2) AS major_comp_pct,
  ROUND(s.median_los_days, 2) AS median_los_days
FROM quintiles q
LEFT JOIN survivor_los s
  ON q.quintile = s.quintile
GROUP BY q.quintile, s.median_los_days
ORDER BY q.quintile;