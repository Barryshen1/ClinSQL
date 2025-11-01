WITH 
-- Step 1: Identify AMI patients within age/gender criteria
ami_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Calculate LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I21.%'  -- AMI codes
),
-- Step 2: Exclude admissions with shock or respiratory failure diagnoses
filtered_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    discharge_location,
    los_days
  FROM ami_admissions
  WHERE hadm_id NOT IN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
      AND (
        icd_code LIKE 'R57%'   -- Shock, unspecified
        OR icd_code LIKE 'I21.4%'  -- Cardiogenic shock
        OR icd_code LIKE 'R65.21%' -- Septic shock
        OR icd_code LIKE 'R65.22%' -- Other septic shock
        OR icd_code LIKE 'R65.29%' -- Other shock
        OR icd_code LIKE 'R96.83%' -- Shock due to blood loss
        OR icd_code LIKE 'R96.84%' -- Shock due to fluid loss
        OR icd_code LIKE 'R96.89%' -- Other shock
        OR icd_code LIKE 'J95.8%'  -- Respiratory failure, unspecified
        OR icd_code LIKE 'J96.9%'  -- Respiratory failure, unspecified
        OR icd_code LIKE 'J98.4%'  -- Respiratory failure in diseases classified elsewhere
        OR icd_code LIKE 'J98.5%'  -- Acute respiratory failure
        OR icd_code LIKE 'J98.6%'  -- Chronic respiratory failure
        OR icd_code LIKE 'J98.7%'  -- Acute and chronic respiratory failure
        OR icd_code LIKE 'J98.8%'  -- Other respiratory failure
        OR icd_code LIKE 'J98.9%'  -- Respiratory failure, unspecified
      )
  )
),
-- Step 3: Categorize LOS into groups
los_groups AS (
  SELECT 
    subject_id,
    hadm_id,
    hospital_expire_flag,
    discharge_location,
    los_days,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '8+ days'
      ELSE 'Other'  -- Shouldn't occur, but included for safety
    END AS los_group
  FROM filtered_admissions
  WHERE los_days >= 1  -- Exclude admissions with LOS <1 day
),
-- Step 4: Compute main metrics per LOS group
main_metrics AS (
  SELECT 
    los_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 1) AS mortality_percent,
    -- Approximate median LOS using 100 buckets for better accuracy
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
  FROM los_groups
  GROUP BY los_group
),
-- Step 5: Compute discharge location counts per LOS group and get top 3
discharge_metrics AS (
  SELECT 
    los_group,
    discharge_location,
    COUNT(*) AS discharge_count
  FROM los_groups
  GROUP BY los_group, discharge_location
),
top_discharges AS (
  SELECT 
    los_group,
    STRING_AGG(
      CONCAT(discharge_location, ': ', CAST(discharge_count AS STRING)), 
      ', ' 
      ORDER BY discharge_count DESC 
      LIMIT 3
    ) AS top_discharge_locations
  FROM discharge_metrics
  GROUP BY los_group
)
-- Step 6: Combine results
SELECT 
  m.los_group,
  m.total_patients,
  m.deaths,
  m.mortality_percent,
  m.median_los,
  t.top_discharge_locations
FROM main_metrics m
LEFT JOIN top_discharges t
  ON m.los_group = t.los_group
ORDER BY 
  CASE m.los_group
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '8+ days' THEN 3
    ELSE 4
  END;