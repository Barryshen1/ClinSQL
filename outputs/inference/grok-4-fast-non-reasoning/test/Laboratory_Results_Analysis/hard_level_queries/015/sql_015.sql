WITH cohort AS (
  -- Base cohort: male, 49-59, ischemic stroke inpatients
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I63%'
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
),

lab_scores AS (
  -- Labs within 72h, compute instability per lab type
  SELECT 
    c.hadm_id,
    l.itemid,
    l.valuenum,
    -- Hardcoded mid-normals for key labs (fallback 0 if ref_range null/unhandled)
    CASE 
      WHEN l.itemid = 225624 THEN 140.0  -- Na (mmol/L)
      WHEN l.itemid = 227464 THEN 4.25   -- K (mmol/L)
      WHEN l.itemid = 225655 THEN 105.0  -- Glucose (mg/dL)
      WHEN l.itemid = 220615 THEN 1.0    -- Creatinine (mg/dL, male)
      WHEN l.itemid = 225651 THEN 13.5   -- BUN (mg/dL)
      WHEN l.itemid = 51237 THEN 1.0     -- INR
      WHEN l.itemid = 50545 THEN 300.0   -- Platelets (x10^3/uL)
      ELSE 0.0
    END AS mid_normal,
    -- Deviation score: relative deviation from mid_normal, capped at 5
    LEAST(ABS((CAST(l.valuenum AS FLOAT64) - mid_normal) / SAFE.NULLIF(mid_normal * 0.1, 0)), 5) AS instability_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  WHERE l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.itemid IN (225624, 227464, 225655, 220615, 225651, 51237, 50545)  -- Key instability labs
    AND li.category = 'Chemistry'
),

admission_scores AS (
  -- Aggregate to admission-level mean instability score (avg across labs; 0 if no labs)
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.anchor_age,
    COALESCE(AVG(ls.instability_score), 0) AS mean_instability_score,
    -- Critical lab rate: % admissions with >=1 abnormal flag in window
    MAX(CASE WHEN ls.instability_score > 2 THEN 1 ELSE 0 END) AS has_critical_lab
  FROM cohort c
  LEFT JOIN lab_scores ls
    ON c.hadm_id = ls.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.anchor_age
),

percentiles AS (
  -- Compute 75th percentile dynamically
  SELECT 
    PERCENTILE_CONT(0.75) OVER() AS p75_score,
    PERCENTILE_CONT(0.25) OVER() AS p25_score
  FROM admission_scores
),

high_instability AS (
  -- High group: score >= p75
  SELECT 
    ascore.*,
    TIMESTAMP_DIFF(ascore.dischtime, ascore.admittime, HOUR) / 24.0 AS los_days
  FROM admission_scores ascore
  CROSS JOIN percentiles p
  WHERE ascore.mean_instability_score >= p.p75_score
),

low_instability AS (
  -- Low group (controls): score < p25 for comparison
  SELECT 
    ascore.*,
    TIMESTAMP_DIFF(ascore.dischtime, ascore.admittime, HOUR) / 24.0 AS los_days
  FROM admission_scores ascore
  CROSS JOIN percentiles p
  WHERE ascore.mean_instability_score < p.p25_score
)

-- Final outputs
SELECT 
  '75th Percentile Instability Score' AS metric,
  p75_score AS value
FROM percentiles

UNION ALL

SELECT 
  CONCAT('High-Instability Group (n=', COUNT(*), ')') AS metric,
  'Mean LOS (days)' AS submetric,
  ROUND(AVG(los_days), 2) AS value
FROM high_instability

UNION ALL

SELECT 
  CONCAT('High-Instability Group (n=', COUNT(*), ')') AS metric,
  'Mortality Rate (%)' AS submetric,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT)) * 100, 2) AS value
FROM high_instability

UNION ALL

SELECT 
  'Critical Lab Rate - High Group (%)' AS metric,
  NULL AS submetric,
  ROUND(AVG(CAST(has_critical_lab AS FLOAT)) * 100, 2) AS value
FROM high_instability

UNION ALL

SELECT 
  CONCAT('Critical Lab Rate - Low Group (Controls, n=', COUNT(*), ') (%)') AS metric,
  NULL AS submetric,
  ROUND(AVG(CAST(has_critical_lab AS FLOAT)) * 100, 2) AS value
FROM low_instability;