WITH 
-- Step 1: Filter patients
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 64 AND 74  -- Adjusted to include the age group 64-74
),

-- Step 2: Get ICU stay details for filtered patients
icu_stays AS (
  SELECT i.stay_id, i.hadm_id, i.intime, i.outtime, 
         DATETIME_DIFF(i.outtime, i.intime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN filtered_patients p ON i.subject_id = p.subject_id
),

-- Step 3: Get admission details
admissions_details AS (
  SELECT a.hadm_id, a.discharge_location, a.deathtime,
         CASE 
           WHEN a.discharge_location = 'HOME' THEN 'Home'
           WHEN a.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/rehab/LTACH'
           ELSE 'Other'
         END AS discharge_group,
         CASE 
           WHEN a.deathtime IS NOT NULL THEN 'In-hospital death'
           ELSE CASE 
                  WHEN a.discharge_location = 'HOME' THEN 'Home'
                  WHEN a.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/rehab/LTACH'
                  ELSE 'Other'
                END
         END AS final_discharge_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN icu_stays i ON a.hadm_id = i.hadm_id
),

-- Step 4: Calculate LOS >= 7 days and prepare for aggregation
los_and_discharge AS (
  SELECT 
    i.los,
    CASE WHEN i.los >= 7 THEN 1 ELSE 0 END AS los_ge_7,
    a.final_discharge_status
  FROM icu_stays i
  JOIN admissions_details a ON i.hadm_id = a.hadm_id
)

-- Step 5: Aggregate data
SELECT 
  final_discharge_status,
  COUNT(CASE WHEN los_ge_7 = 1 THEN 1 END) AS count_los_ge_7,
  COUNT(*) AS total_count,
  COUNT(CASE WHEN los_ge_7 = 1 THEN 1 END) / COUNT(*) AS proportion_los_ge_7,
  APPROX_QUANTILES(los, 100)[OFFSET(14)] AS percentile_14_day
FROM los_and_discharge
GROUP BY final_discharge_status;