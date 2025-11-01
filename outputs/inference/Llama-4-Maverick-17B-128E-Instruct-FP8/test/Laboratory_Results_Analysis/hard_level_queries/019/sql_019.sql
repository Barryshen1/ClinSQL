WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND dicd.long_title LIKE '%Acute pancreatitis%'
),

-- Step 2: Calculate the 72-h lab-instability score
lab_instability AS (
  SELECT c.hadm_id, 
         -- Example calculation: count of labs outside normal range within 72h
         SUM(CASE WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 ELSE 0 END) AS lab_instability_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),

-- Step 3: Determine the 90th percentile of the lab-instability score
percentile_90 AS (
  SELECT APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(90)] AS p90_score
  FROM lab_instability
),

-- Step 4: Analyze outcomes for patients >= P90
outcomes AS (
  SELECT 
    li.hadm_id,
    a.hospital_expire_flag AS mortality,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    -- Example critical lab definition
    CASE WHEN li.lab_instability_score >= (SELECT p90_score FROM percentile_90) THEN 1 ELSE 0 END AS is_high_risk
  FROM lab_instability li
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON li.hadm_id = a.hadm_id
)

-- Final query
SELECT 
  -- Mortality rate for high-risk patients
  AVG(CASE WHEN is_high_risk = 1 THEN mortality ELSE NULL END) AS mortality_high_risk,
  -- Mean LOS for high-risk patients
  AVG(CASE WHEN is_high_risk = 1 THEN los_hours ELSE NULL END) / 24 AS mean_los_days_high_risk,
  -- Per-lab critical rates for high-risk vs. general population
  SUM(CASE WHEN is_high_risk = 1 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_high_risk,
  -- General population metrics for comparison
  AVG(mortality) AS mortality_general,
  AVG(los_hours) / 24 AS mean_los_days_general
FROM outcomes;