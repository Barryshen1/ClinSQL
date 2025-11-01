WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND di.icd_code IN ('K922', 'K625', 'K621', 'K920', 'K921')
    AND di.icd_version = 10
),

labs AS (
  SELECT 
    c.hadm_id,
    le.charttime,
    dli.label,
    le.valuenum,
    -- Define critical thresholds (adjusted for clinical relevance)
    CASE 
      WHEN dli.label = 'Creatinine' AND le.valuenum > 1.5 THEN 1  -- Increased threshold for elderly
      WHEN dli.label = 'Potassium' AND (le.valuenum < 3.0 OR le.valuenum > 5.5) THEN 1  -- Wider range
      WHEN dli.label = 'Platelets' AND le.valuenum < 100 THEN 1  -- More clinically significant
      WHEN dli.label = 'Hemoglobin' AND le.valuenum < 8.0 THEN 1
      WHEN dli.label = 'Whole Blood Potassium' AND (le.valuenum < 3.0 OR le.valuenum > 5.5) THEN 1
      WHEN dli.label = 'White Blood Cells' AND (le.valuenum < 2.0 OR le.valuenum > 15.0) THEN 1  -- Wider range
      ELSE 0
    END AS is_critical
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.label IN (
      'Creatinine', 'Potassium', 'Platelets', 
      'Hemoglobin', 'Whole Blood Potassium', 'White Blood Cells'
    )
    AND le.valuenum IS NOT NULL
),

lab_sequences AS (
  SELECT 
    hadm_id,
    label,
    charttime,
    valuenum,
    LAG(valuenum) OVER (PARTITION BY hadm_id, label ORDER BY charttime) AS prev_value
  FROM labs
),

instability_calc AS (
  SELECT 
    hadm_id,
    label,
    SUM(ABS(valuenum - prev_value)) AS lab_instability
  FROM lab_sequences
  WHERE prev_value IS NOT NULL
  GROUP BY hadm_id, label
),

instability_score AS (
  SELECT 
    hadm_id,
    SUM(lab_instability) AS instability_score
  FROM instability_calc
  GROUP BY hadm_id
),

p90_value AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score
  FROM instability_score
),

top_tier AS (
  SELECT 
    hadm_id
  FROM instability_score
  CROSS JOIN p90_value
  WHERE instability_score >= p90_score
)

-- Main analysis
SELECT 
  'Mortality and LOS' AS analysis_type,
  CASE WHEN tt.hadm_id IS NOT NULL THEN 'Top-tier' ELSE 'All inpatients' END AS cohort,
  COUNT(DISTINCT c.hadm_id) AS n_patients,
  SUM(c.hospital_expire_flag) AS mortality,
  AVG(c.los_days) AS avg_los_days,
  NULL AS label,
  NULL AS total_measurements,
  NULL AS critical_measurements,
  NULL AS critical_rate
FROM cohort c
LEFT JOIN top_tier tt ON c.hadm_id = tt.hadm_id
GROUP BY cohort

UNION ALL

-- Lab analysis
SELECT 
  'Lab critical rates' AS analysis_type,
  CASE WHEN tt.hadm_id IS NOT NULL THEN 'Top-tier' ELSE 'All inpatients' END AS cohort,
  NULL AS n_patients,
  NULL AS mortality,
  NULL AS avg_los_days,
  l.label,
  COUNT(*) AS total_measurements,
  SUM(l.is_critical) AS critical_measurements,
  SAFE_DIVIDE(SUM(l.is_critical), COUNT(*)) AS critical_rate
FROM labs l
LEFT JOIN top_tier tt ON l.hadm_id = tt.hadm_id
GROUP BY cohort, l.label

ORDER BY analysis_type, cohort, label;