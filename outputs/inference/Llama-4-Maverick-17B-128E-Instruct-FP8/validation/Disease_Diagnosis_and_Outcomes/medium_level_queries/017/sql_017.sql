WITH 
-- Step 1: Identify patients with sepsis
sepsis_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Sepsis%' OR d_icd.long_title LIKE '%septic%'
),
-- Step 2: Exclude patients with septic shock
septic_shock_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%septic shock%'
),
-- Step 3: Cohort definition
cohort AS (
  SELECT pat.subject_id, adm.hadm_id, 
         CASE 
           WHEN pat.anchor_age BETWEEN 50 AND 60 AND pat.gender = 'M' THEN 1 
           ELSE 0 
         END AS eligible,
         adm.hospital_expire_flag,
         DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) AS time_to_death,
         icu.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON pat.subject_id = adm.subject_id
  JOIN sepsis_patients ON adm.hadm_id = sepsis_patients.hadm_id
  LEFT JOIN septic_shock_patients ON adm.hadm_id = septic_shock_patients.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON adm.hadm_id = icu.hadm_id
  WHERE septic_shock_patients.hadm_id IS NULL
),
-- Step 4: Calculate mortality and time-to-death by LOS group
results AS (
  SELECT 
    CASE WHEN los < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    APPROX_QUANTILES(time_to_death, 100)[OFFSET(50)] AS median_time_to_death
  FROM cohort
  WHERE eligible = 1
  GROUP BY los_group
)

-- Final query to get the required statistics
SELECT 
  los_group,
  (deaths / total_patients) * 100 AS mortality_percent,
  -- Using a simpler method for 95% CI, consider using a more precise method if needed
  ((deaths / total_patients) * 100) - 1.96 * SQRT((deaths / total_patients) * (1 - (deaths / total_patients)) / total_patients) * 100 AS mortality_ci_lower,
  ((deaths / total_patients) * 100) + 1.96 * SQRT((deaths / total_patients) * (1 - (deaths / total_patients)) / total_patients) * 100 AS mortality_ci_upper,
  median_time_to_death
FROM results;