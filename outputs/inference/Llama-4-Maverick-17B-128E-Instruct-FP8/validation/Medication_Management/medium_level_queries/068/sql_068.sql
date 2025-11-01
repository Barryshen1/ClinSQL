WITH 
-- Step 1: Identify patients with T2DM and HF
diabetes_patients AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 AND icd_code LIKE 'E11%'
),
heart_failure_patients AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 AND icd_code LIKE 'I50%'
),
target_population AS (
  SELECT p.subject_id, p.gender, EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 83 AND 93
  AND p.subject_id IN (SELECT subject_id FROM diabetes_patients)
  AND p.subject_id IN (SELECT subject_id FROM heart_failure_patients)
),

-- Step 2: Analyze ICU stays and insulin administration
icu_stays AS (
  SELECT i.subject_id, i.stay_id, i.intime, i.outtime,
         TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN target_population t ON i.subject_id = t.subject_id
),
insulin_administration AS (
  SELECT i.subject_id, i.stay_id, i.intime, i.outtime, ie.starttime, ie.itemid
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.ingredientevents` ie ON i.stay_id = ie.stay_id
  WHERE ie.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Insulin%')
),

-- Step 3: Determine insulin regimen in first 48 hours and last 12 hours
insulin_first_48h AS (
  SELECT subject_id, stay_id, COUNT(DISTINCT itemid) AS num_insulin_types
  FROM insulin_administration
  WHERE starttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 48 HOUR)
  GROUP BY subject_id, stay_id
),
insulin_last_12h AS (
  SELECT subject_id, stay_id, COUNT(DISTINCT itemid) AS num_insulin_types
  FROM insulin_administration
  WHERE starttime BETWEEN TIMESTAMP_SUB(outtime, INTERVAL 12 HOUR) AND outtime
  GROUP BY subject_id, stay_id
)

-- Final analysis
SELECT 
  'First 48h' AS period,
  COUNT(CASE WHEN num_insulin_types = 1 THEN 1 END) AS basal_or_bolus,
  COUNT(CASE WHEN num_insulin_types > 1 THEN 1 END) AS basal_bolus,
  COUNT(CASE WHEN num_insulin_types = 1 AND stay_id IN (SELECT stay_id FROM insulin_administration WHERE itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Sliding%')) THEN 1 END) AS sliding_scale
FROM insulin_first_48h
UNION ALL
SELECT 
  'Last 12h' AS period,
  COUNT(CASE WHEN num_insulin_types = 1 THEN 1 END) AS basal_or_bolus,
  COUNT(CASE WHEN num_insulin_types > 1 THEN 1 END) AS basal_bolus,
  COUNT(CASE WHEN num_insulin_types = 1 AND stay_id IN (SELECT stay_id FROM insulin_administration WHERE itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Sliding%')) THEN 1 END) AS sliding_scale
FROM insulin_last_12h;