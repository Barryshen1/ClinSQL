WITH cohort AS (
  -- Male inpatients aged 68-78
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
),

relevant_labs AS (
  -- Key lab itemids (standard MIMIC-IV)
  SELECT 50912 AS itemid, 'Cr' AS lab_name  -- Creatinine
  UNION ALL SELECT 50971, 'K'               -- Potassium (serum; whole-blood K in chartevents if needed)
  UNION ALL SELECT 51265, 'Platelets'       -- Platelets
  UNION ALL SELECT 51222, 'Hgb'             -- Hemoglobin (corrected itemid)
  UNION ALL SELECT 51301, 'WBC'             -- WBC
),

lab_values AS (
  -- Labs within 72h of admission for cohort
  SELECT 
    c.hadm_id,
    l.itemid,
    l.valuenum,
    l.valueuom,
    l.ref_range_lower,
    l.ref_range_upper,
    l.flag
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  INNER JOIN 
    relevant_labs r
    ON l.itemid = r.itemid
  WHERE 
    l.valuenum IS NOT NULL
    AND l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (l.flag IS NULL OR l.flag <> 'error')  -- Exclude obvious errors
),

deviations AS (
  -- Max deviation per lab type per admission (normalized instability)
  SELECT 
    hadm_id,
    itemid,
    MAX(
      GREATEST(
        SAFE_DIVIDE(
          ABS(valuenum - (COALESCE(ref_range_lower, 0) + COALESCE(ref_range_upper, 0)) / 2.0),
          GREATEST((COALESCE(ref_range_upper, 0) - COALESCE(ref_range_lower, 0)) / 2.0, 0.1)  -- Avoid div/0, min width 0.1
        ), 0
      )
    ) AS max_deviation
  FROM 
    lab_values
  GROUP BY hadm_id, itemid
),

admission_scores AS (
  -- Sum deviations for 72h instability score per admission
  SELECT 
    c.hadm_id,
    COALESCE(SUM(d.max_deviation), 0) AS instability_score,
    c.hospital_expire_flag,
    DATE_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM 
    cohort c
  LEFT JOIN 
    deviations d
    ON c.hadm_id = d.hadm_id
  GROUP BY c.hadm_id, c.hospital_expire_flag, c.dischtime, c.admittime
),

percentile_90 AS (
  SELECT 
    PERCENTILE_CONT(0.9, instability_score) OVER () AS p90_score
  FROM 
    admission_scores
  LIMIT 1  -- Scalar value
),

top_tier AS (
  -- Admissions >= p90
  SELECT 
    ascore.*
  FROM 
    admission_scores ascore
  CROSS JOIN 
    percentile_90 p90
  WHERE 
    ascore.instability_score >= p90.p90_score
),

all_inpatients AS (
  -- All inpatient admissions for comparison
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE 
    admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
),

all_inpatient_labs AS (
  -- 72h labs for all inpatients (same logic)
  SELECT 
    ai.hadm_id,
    l.itemid,
    r.lab_name,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM 
    all_inpatients ai
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON ai.hadm_id = l.hadm_id
  INNER JOIN 
    relevant_labs r
    ON l.itemid = r.itemid
  WHERE 
    l.valuenum IS NOT NULL
    AND l.charttime BETWEEN ai.admittime AND TIMESTAMP_ADD(ai.admittime, INTERVAL 72 HOUR)
),

all_critical AS (
  -- % admissions with >=1 critical value per lab (all inpatients)
  SELECT 
    r.itemid,
    r.lab_name,
    COUNT(DISTINCT CASE WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN l.hadm_id END) * 100.0 / COUNT(DISTINCT l.hadm_id) AS critical_rate_pct
  FROM 
    all_inpatient_labs l
  INNER JOIN 
    relevant_labs r ON l.itemid = r.itemid
  GROUP BY r.itemid, r.lab_name
),

top_critical AS (
  -- Same for top-tier
  SELECT 
    lv.itemid,
    r.lab_name,
    COUNT(DISTINCT CASE WHEN lv.valuenum < lv.ref_range_lower OR lv.valuenum > lv.ref_range_upper THEN tt.hadm_id END) * 100.0 / COUNT(DISTINCT tt.hadm_id) AS critical_rate_pct
  FROM 
    top_tier tt
  INNER JOIN 
    lab_values lv
    ON tt.hadm_id = lv.hadm_id
  INNER JOIN 
    relevant_labs r
    ON lv.itemid = r.itemid
  GROUP BY lv.itemid, r.lab_name
)

-- Main results
SELECT 
  '90th Percentile 72h Lab-Instability Score' AS metric,
  ROUND(p90.p90_score, 2) AS value
FROM percentile_90 p90

UNION ALL

SELECT 
  'Top-Tier Mortality (%)' AS metric,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS value
FROM top_tier

UNION ALL

SELECT 
  'Top-Tier Avg LOS (days)' AS metric,
  ROUND(AVG(los_days), 2) AS value
FROM top_tier

UNION ALL

-- Critical rates comparison (top-tier vs all)
SELECT 
  CONCAT(tc.lab_name, ' Critical Rate Top-Tier (%)') AS metric,
  ROUND(tc.critical_rate_pct, 2) AS value
FROM top_critical tc

UNION ALL

SELECT 
  CONCAT(ac.lab_name, ' Critical Rate All Inpatients (%)') AS metric,
  ROUND(ac.critical_rate_pct, 2) AS value
FROM all_critical ac

ORDER BY metric;