WITH 
-- Step 1: Patient selection and basic demographics
patients_selected AS (
  SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.anchor_age = 44 AND p.gender = 'M'
),

-- Step 2: Identify ICU stays
icu_stays AS (
  SELECT hadm_id, COUNT(stay_id) AS icu_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

-- Step 3: Calculate LOS and categorize it
los_categorized AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) <= 3 THEN '≤3'
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 6 THEN '4-6'
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_category
  FROM patients_selected
),

-- Step 4: Simplified Charlson Comorbidity Index (using diagnoses_icd)
charlson_score AS (
  SELECT 
    di.hadm_id,
    -- Simplified Charlson score calculation based on ICD codes
    -- This is a very simplified version and may not cover all conditions and weights accurately
    SUM(CASE 
      WHEN dicd.icd_code IN ('410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9') THEN 1
      -- Add more conditions and weights as needed
      ELSE 0
    END) AS charlson
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  GROUP BY di.hadm_id
),

-- Step 5: Identify treatments (simplified examples)
treatments AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Ventilator%') THEN 1 ELSE 0 END) AS mechanical_ventilation,
    MAX(CASE WHEN itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Vasopressor%') THEN 1 ELSE 0 END) AS vasopressors,
    MAX(CASE WHEN itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%RRT%') THEN 1 ELSE 0 END) AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  GROUP BY hadm_id
  UNION ALL
  SELECT 
    hadm_id,
    0 AS mechanical_ventilation,
    MAX(CASE WHEN lower(drug) LIKE '%vasopressor%' THEN 1 ELSE 0 END) AS vasopressors,
    0 AS rrt
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY hadm_id
),

-- Main query
final_data AS (
  SELECT 
    ps.hadm_id,
    COALESCE(icu_stays.icu_count, 0) > 0 AS icu_admission,
    los_categorized.los_category,
    CASE 
      WHEN charlson_score.charlson <= 3 THEN '≤3'
      WHEN charlson_score.charlson BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_category,
    ps.hospital_expire_flag,
    COALESCE(treatments.mechanical_ventilation, 0) AS mechanical_ventilation,
    COALESCE(treatments.vasopressors, 0) AS vasopressors,
    COALESCE(treatments.rrt, 0) AS rrt
  FROM patients_selected ps
  LEFT JOIN icu_stays ON ps.hadm_id = icu_stays.hadm_id
  JOIN los_categorized ON ps.hadm_id = los_categorized.hadm_id
  JOIN charlson_score ON ps.hadm_id = charlson_score.hadm_id
  LEFT JOIN treatments ON ps.hadm_id = treatments.hadm_id
)

SELECT 
  icu_admission,
  los_category,
  charlson_category,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS in_hospital_deaths,
  SUM(hospital_expire_flag) / COUNT(*) * 100 AS mortality_percentage,
  SUM(mechanical_ventilation) / COUNT(*) * 100 AS mechanical_ventilation_percentage,
  SUM(vasopressors) / COUNT(*) * 100 AS vasopressors_percentage,
  SUM(rrt) / COUNT(*) * 100 AS rrt_percentage
FROM final_data
GROUP BY icu_admission, los_category, charlson_category
ORDER BY icu_admission, los_category, charlson_category;