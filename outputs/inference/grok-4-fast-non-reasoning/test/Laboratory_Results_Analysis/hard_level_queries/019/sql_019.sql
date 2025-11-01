WITH eligible_admissions AS (
  -- First admission per subject, male 63-73
  SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag,
         gender, anchor_age,
         DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS los_days
  FROM (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
           p.gender, p.anchor_age,
           ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 63 AND 73
      AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
  ) ranked
  WHERE rn = 1
),

ap_cohort AS (
  -- Target: AP patients
  SELECT e.*, 1 AS is_ap
  FROM eligible_admissions e
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON e.subject_id = d.subject_id AND e.hadm_id = d.hadm_id
  WHERE d.icd_code LIKE 'K85%' AND d.icd_version = '10'
),

general_cohort AS (
  -- General: all eligible without AP
  SELECT e.*, 0 AS is_ap
  FROM eligible_admissions e
  WHERE NOT EXISTS (
    SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    WHERE d.subject_id = e.subject_id AND d.hadm_id = e.hadm_id 
      AND d.icd_code LIKE 'K85%' AND d.icd_version = '10'
  )
),

all_cohort AS (
  SELECT * FROM ap_cohort
  UNION ALL
  SELECT * FROM general_cohort
),

lab_data AS (
  -- Labs in first 72h, relevant itemids for AP/critical panels
  SELECT 
    c.subject_id, c.hadm_id, c.is_ap, c.admittime,
    l.itemid, l.charttime, l.valuenum,
    li.label,
    -- Binary critical flags (adjusted to standard critical ranges)
    CASE 
      WHEN l.itemid IN (50869, 50861, 50893) AND l.valuenum > 125 THEN 1  -- Amylase >125 U/L (ULN)
      WHEN l.itemid IN (50875, 51166) AND l.valuenum > 60 THEN 1  -- Lipase >60 U/L (ULN)
      WHEN l.itemid IN (26464021, 5131) AND (l.valuenum > 12 OR l.valuenum < 4) THEN 1  -- WBC k/uL
      WHEN l.itemid IN (50931, 225624) AND (l.valuenum > 500 OR l.valuenum < 70) THEN 1  -- Glucose mg/dL
      WHEN l.itemid IN (50983, 226730) AND (l.valuenum > 150 OR l.valuenum < 130) THEN 1  -- Sodium mmol/L
      WHEN l.itemid IN (50971, 227464) AND (l.valuenum > 6 OR l.valuenum < 2.5) THEN 1  -- Potassium mmol/L
      WHEN l.itemid IN (51006, 227395) AND l.valuenum > 50 THEN 1  -- BUN mg/dL
      WHEN l.itemid IN (50912, 227551) AND l.valuenum > 2.0 THEN 1  -- Creatinine mg/dL
      ELSE 0
    END AS is_critical
  FROM all_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 3 DAY)
    AND l.valuenum IS NOT NULL
    AND l.itemid IN (50869, 50861, 50893, 50875, 51166, 26464021, 5131, 50931, 225624, 50983, 226730, 50971, 227464, 51006, 227395, 50912, 227551)
    AND li.category IN ('Chemistry', 'Hematology')
  -- Dedup: first per itemid per 24h
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id, l.itemid, DATE(l.charttime) ORDER BY l.charttime) = 1
),

per_adm_critical AS (
  SELECT 
    ld.subject_id, ld.hadm_id, ld.is_ap,
    MAX(CASE WHEN ld.itemid IN (50869, 50861, 50893) AND ld.is_critical = 1 THEN 1 ELSE 0 END) AS amylase_critical,
    MAX(CASE WHEN ld.itemid IN (50875, 51166) AND ld.is_critical = 1 THEN 1 ELSE 0 END) AS lipase_critical,
    MAX(CASE WHEN ld.itemid IN (26464021, 5131) AND ld.is_critical = 1 THEN 1 ELSE 0 END) AS wbc_critical,
    MAX(CASE WHEN ld.itemid IN (50931, 225624) AND ld.is_critical = 1 THEN 1 ELSE 0 END) AS glucose_critical,
    MAX(CASE WHEN ld.itemid IN (50983, 226730) AND ld.is_critical = 1 THEN 1 ELSE 0 END) AS sodium_critical,
    MAX(CASE WHEN ld.itemid IN (50971, 227464) AND ld.is_critical = 1 THEN 1 ELSE 0 END) AS potassium_critical,
    MAX(CASE WHEN ld.itemid IN (51006, 227395) AND ld.is_critical = 1 THEN 1 ELSE 0 END) AS bun_critical,
    MAX(CASE WHEN ld.itemid IN (50912, 227551) AND ld.is_critical = 1 THEN 1 ELSE 0 END) AS creatinine_critical
  FROM lab_data ld
  GROUP BY ld.subject_id, ld.hadm_id, ld.is_ap
),

scores AS (
  -- Aggregate score per admission
  SELECT 
    pac.subject_id, pac.hadm_id, pac.is_ap,
    (amylase_critical + lipase_critical + wbc_critical + glucose_critical + sodium_critical + 
     potassium_critical + bun_critical + creatinine_critical) AS instability_score,
    pac.amylase_critical, pac.lipase_critical, pac.wbc_critical, pac.glucose_critical,
    pac.sodium_critical, pac.potassium_critical, pac.bun_critical, pac.creatinine_critical
  FROM per_adm_critical pac
  UNION ALL
  -- No labs: score=0
  SELECT subject_id, hadm_id, is_ap, 0 AS instability_score,
         0, 0, 0, 0, 0, 0, 0, 0
  FROM all_cohort
  WHERE hadm_id NOT IN (SELECT hadm_id FROM lab_data)
),

scores_with_outcomes AS (
  SELECT 
    s.*, e.los_days, e.hospital_expire_flag
  FROM scores s
  JOIN eligible_admissions e ON s.subject_id = e.subject_id AND s.hadm_id = e.hadm_id
),

p90_threshold AS (
  SELECT PERCENTILE_CONT(instability_score, 0.9) OVER () AS p90_score
  FROM scores_with_outcomes
  WHERE is_ap = 1
),

p90_ap AS (
  SELECT s.*
  FROM scores_with_outcomes s
  CROSS JOIN p90_threshold p
  WHERE s.is_ap = 1 AND s.instability_score >= p.p90_score
),

general_metrics AS (
  SELECT 
    'General' AS cohort_label,
    AVG(los_days) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(CAST(amylase_critical AS FLOAT64)) AS amylase_critical_rate,
    AVG(CAST(lipase_critical AS FLOAT64)) AS lipase_critical_rate,
    AVG(CAST(wbc_critical AS FLOAT64)) AS wbc_critical_rate,
    AVG(CAST(glucose_critical AS FLOAT64)) AS glucose_critical_rate,
    AVG(CAST(sodium_critical AS FLOAT64)) AS sodium_critical_rate,
    AVG(CAST(potassium_critical AS FLOAT64)) AS potassium_critical_rate,
    AVG(CAST(bun_critical AS FLOAT64)) AS bun_critical_rate,
    AVG(CAST(creatinine_critical AS FLOAT64)) AS creatinine_critical_rate
  FROM scores_with_outcomes
  WHERE is_ap = 0
),

p90_metrics AS (
  SELECT 
    'P90 AP' AS cohort_label,
    AVG(los_days) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(CAST(amylase_critical AS FLOAT64)) AS amylase_critical_rate,
    AVG(CAST(lipase_critical AS FLOAT64)) AS lipase_critical_rate,
    AVG(CAST(wbc_critical AS FLOAT64)) AS wbc_critical_rate,
    AVG(CAST(glucose_critical AS FLOAT64)) AS glucose_critical_rate,
    AVG(CAST(sodium_critical AS FLOAT64)) AS sodium_critical_rate,
    AVG(CAST(potassium_critical AS FLOAT64)) AS potassium_critical_rate,
    AVG(CAST(bun_critical AS FLOAT64)) AS bun_critical_rate,
    AVG(CAST(creatinine_critical AS FLOAT64)) AS creatinine_critical_rate
  FROM p90_ap
)

-- Final output
SELECT 
  (SELECT p90_score FROM p90_threshold) AS ap_90th_percentile_score,
  m.cohort_label,
  ROUND(m.mean_los, 2) AS mean_los_days,
  ROUND(m.mortality_rate * 100, 2) AS mortality_rate_percent,
  ROUND(m.amylase_critical_rate * 100, 2) AS amylase_critical_rate_percent,
  ROUND(m.lipase_critical_rate * 100, 2) AS lipase_critical_rate_percent,
  ROUND(m.wbc_critical_rate * 100, 2) AS wbc_critical_rate_percent,
  ROUND(m.glucose_critical_rate * 100, 2) AS glucose_critical_rate_percent,
  ROUND(m.sodium_critical_rate * 100, 2) AS sodium_critical_rate_percent,
  ROUND(m.potassium_critical_rate * 100, 2) AS potassium_critical_rate_percent,
  ROUND(m.bun_critical_rate * 100, 2) AS bun_critical_rate_percent,
  ROUND(m.creatinine_critical_rate * 100, 2) AS creatinine_critical_rate_percent
FROM p90_metrics m
UNION ALL
SELECT 
  (SELECT p90_score FROM p90_threshold) AS ap_90th_percentile_score,
  g.cohort_label,
  ROUND(g.mean_los, 2) AS mean_los_days,
  ROUND(g.mortality_rate * 100, 2) AS mortality_rate_percent,
  ROUND(g.amylase_critical_rate * 100, 2) AS amylase_critical_rate_percent,
  ROUND(g.lipase_critical_rate * 100, 2) AS lipase_critical_rate_percent,
  ROUND(g.wbc_critical_rate * 100, 2) AS wbc_critical_rate_percent,
  ROUND(g.glucose_critical_rate * 100, 2) AS glucose_critical_rate_percent,
  ROUND(g.sodium_critical_rate * 100, 2) AS sodium_critical_rate_percent,
  ROUND(g.potassium_critical_rate * 100, 2) AS potassium_critical_rate_percent,
  ROUND(g.bun_critical_rate * 100, 2) AS bun_critical_rate_percent,
  ROUND(g.creatinine_critical_rate * 100, 2) AS creatinine_critical_rate_percent
FROM general_metrics g
ORDER BY cohort_label;