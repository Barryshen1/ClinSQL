WITH cohort AS (
  -- Base cohort: females 75-85 with primary COPD exacerbation admission
  SELECT DISTINCT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    CASE WHEN a.admission_type IN ('EMERGENCY', 'URGENT') THEN 1 ELSE 0 END AS urgency_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_type != 'NEWBORN'
    AND icd.icd_version = '10'
    AND icd.icd_code LIKE 'J44%'
),

comorbidities AS (
  -- Count comorbidities per admission (fixed type consistency)
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT CASE 
      WHEN diag.icd_code LIKE 'D5[0-6]%' OR diag.icd_code LIKE 'D[5-6][0-9]%' THEN 1
      WHEN diag.icd_code = 'I50' THEN 1
      WHEN diag.icd_code LIKE 'E1[0-4]%' THEN 1
    END) AS comorb_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON c.hadm_id = diag.hadm_id AND diag.icd_version = '10'
  GROUP BY c.hadm_id
),

risk_scores AS (
  -- Composite risk score per admission, with quartile (age normalized)
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    (c.anchor_age / 10.0 + c.urgency_flag + COALESCE(com.comorb_count, 0)) AS risk_score,
    NTILE(4) OVER (ORDER BY (c.anchor_age / 10.0 + c.urgency_flag + COALESCE(com.comorb_count, 0))) AS quartile
  FROM cohort c
  LEFT JOIN comorbidities com ON c.hadm_id = com.hadm_id
),

mortality AS (
  -- 90-day mortality per admission (fixed date handling)
  SELECT 
    rs.hadm_id,
    rs.quartile,
    CASE 
      WHEN p.dod IS NOT NULL 
        AND p.dod <= DATE_ADD(PARSE_DATE('%Y-%m-%d', rs.dischtime), INTERVAL 90 DAY) 
      THEN 1 ELSE 0 
    END AS died_90d
  FROM risk_scores rs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON rs.subject_id = p.subject_id
),

complications AS (
  -- Major complications per admission (added death check)
  SELECT 
    rs.hadm_id,
    rs.quartile,
    CASE 
      WHEN rs.hospital_expire_flag = 1 
        OR EXISTS (
          SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
          WHERE proc.hadm_id = rs.hadm_id AND proc.icd_version = '10' AND proc.icd_code LIKE '5A19%'
        )
        OR EXISTS (
          SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
          WHERE diag.hadm_id = rs.hadm_id AND diag.icd_version = '10' AND diag.icd_code LIKE 'J96%'
            AND rs.hospital_expire_flag = 0  -- Avoid double-counting death
        )
      THEN 1 ELSE 0 
    END AS major_comp
  FROM risk_scores rs
),

los_survivors AS (
  -- LOS for survivors only (fixed diff calculation)
  SELECT 
    rs.hadm_id,
    rs.quartile,
    EXTRACT(DAY FROM (TIMESTAMP(rs.dischtime) - TIMESTAMP(rs.admittime))) AS los_days
  FROM risk_scores rs
  WHERE rs.hospital_expire_flag = 0 AND EXTRACT(DAY FROM (TIMESTAMP(rs.dischtime) - TIMESTAMP(rs.admittime))) > 0
),

-- Aggregates per quartile
quartile_agg AS (
  SELECT 
    m.quartile,
    ROUND(AVG(m.died_90d) * 100, 2) AS mortality_90d_pct,
    ROUND(AVG(comp.major_comp) * 100, 2) AS major_comp_rate_pct,
    PERCENTILE_CONT(los_days, 0.5) AS median_los_days,
    COUNT(DISTINCT CASE WHEN m.died_90d = 1 THEN rs.hadm_id END) AS n_deaths_90d,
    COUNT(DISTINCT rs.hadm_id) AS n_admissions
  FROM risk_scores rs
  INNER JOIN mortality m ON rs.hadm_id = m.hadm_id
  INNER JOIN complications comp ON rs.hadm_id = comp.hadm_id
  LEFT JOIN los_survivors l ON rs.hadm_id = l.hadm_id AND m.quartile = l.quartile
  GROUP BY m.quartile
),

-- Broader 90-day mortality (overall)
overall_mortality AS (
  SELECT 
    0 AS quartile,
    ROUND(AVG(died_90d) * 100, 2) AS mortality_90d_pct,
    NULL AS major_comp_rate_pct,
    NULL AS median_los_days,
    COUNT(DISTINCT CASE WHEN died_90d = 1 THEN hadm_id END) AS n_deaths_90d,
    COUNT(DISTINCT hadm_id) AS n_admissions
  FROM mortality
)

-- Final results
SELECT * FROM quartile_agg
UNION ALL
SELECT * FROM overall_mortality
ORDER BY quartile;