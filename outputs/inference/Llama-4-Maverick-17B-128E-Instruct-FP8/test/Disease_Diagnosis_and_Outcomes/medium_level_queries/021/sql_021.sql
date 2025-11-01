WITH 
-- Step 1: Filter patients
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 60 AND 70
),

-- Step 2: Identify postoperative patients (simplified)
postop_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
),

-- Step 3: Determine ICU status and LOS
icu_los AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    icu.stay_id IS NOT NULL AS is_icu,
    COALESCE(DATE_DIFF(icu.outtime, icu.intime, DAY), DATE_DIFF(a.dischtime, a.admittime, DAY)) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM postop_patients)
  AND a.subject_id IN (SELECT subject_id FROM patients_filtered)
),

-- Step 4: Calculate Charlson score (simplified)
charlson_score AS (
  SELECT 
    di.hadm_id,
    SUM(CASE 
      WHEN d.icd_code IN ('410.01', '410.11', '410.21', '410.31', '410.41', '410.51', '410.61', '410.71', '410.81', '410.91') THEN 1  -- Myocardial infarction
      WHEN d.icd_code LIKE '428%' THEN 1  -- Congestive heart failure
      -- Add more conditions here...
      ELSE 0
    END) AS charlson
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY di.hadm_id
),

-- Step 5: Combine data and calculate required metrics
combined_data AS (
  SELECT 
    il.is_icu,
    il.los,
    cs.charlson,
    il.deathtime IS NOT NULL AS hospital_mortality,
    DATE_DIFF(il.deathtime, il.admittime, DAY) AS time_to_death
  FROM icu_los il
  JOIN charlson_score cs ON il.hadm_id = cs.hadm_id
)

SELECT 
  is_icu,
  CASE 
    WHEN los BETWEEN 1 AND 3 THEN '1-3'
    WHEN los BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END AS los_category,
  CASE 
    WHEN charlson <= 3 THEN '<=3'
    WHEN charlson BETWEEN 4 AND 5 THEN '4-5'
    ELSE '>5'
  END AS charlson_category,
  COUNT(*) AS N,
  AVG(hospital_mortality) * 100 AS in_hospital_mortality_pct,
  APPROX_QUANTILES(time_to_death, 100)[OFFSET(50)] AS median_time_to_death
FROM combined_data
GROUP BY is_icu, los_category, charlson_category
ORDER BY is_icu, los_category, charlson_category;