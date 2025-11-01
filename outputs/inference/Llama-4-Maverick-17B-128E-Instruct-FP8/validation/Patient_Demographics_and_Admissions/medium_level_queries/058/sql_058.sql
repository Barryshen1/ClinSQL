WITH 
-- Step 1: Filter patients based on age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 37 AND 47
),

-- Step 2: Identify transfer-ins and their admission details
transfer_ins AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.discharge_location,
         CASE 
           WHEN a.discharge_location = 'HOME' THEN 'Home'
           WHEN a.discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'LONG TERM CARE HOSPITAL') THEN 'SNF/rehab/LTACH'
           ELSE 'Other'
         END AS discharge_category,
         CASE WHEN a.deathtime IS NOT NULL THEN 'In-hospital Mortality' ELSE 'Survived' END AS mortality_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
  WHERE a.admission_location = 'TRANSFER FROM HOSPITAL'
),

-- Step 3: Calculate LOS and prepare data for analysis
patient_data AS (
  SELECT hadm_id, discharge_category, mortality_status,
         DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM transfer_ins
),

-- Step 4: Calculate required statistics and percentile rank
stats AS (
  SELECT 
    discharge_category,
    COUNT(*) AS n,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_los,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
    APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95_los
  FROM patient_data
  GROUP BY discharge_category
),

percentile_ranks AS (
  SELECT discharge_category, los, PERCENT_RANK() OVER (PARTITION BY discharge_category ORDER BY los) AS percentile_rank
  FROM patient_data
)

-- Step 5: Combine results
SELECT 
  s.discharge_category,
  s.n,
  s.mean_los,
  s.p25_los,
  s.median_los,
  s.p75_los,
  s.p90_los,
  s.p95_los,
  pr.percentile_rank AS percentile_rank_5day
FROM stats s
JOIN percentile_ranks pr ON s.discharge_category = pr.discharge_category
WHERE pr.los = 5
ORDER BY s.discharge_category;