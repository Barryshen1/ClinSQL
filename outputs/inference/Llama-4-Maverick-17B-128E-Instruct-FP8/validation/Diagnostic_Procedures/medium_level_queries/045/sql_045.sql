WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT DISTINCT p.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON p.subject_id = di.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 78 AND 88
  AND (dicd.long_title LIKE '%deep vein thrombosis%' OR dicd.long_title LIKE '%DVT%')
),

-- Step 2: Calculate LOS and identify ICU stays
admissions_info AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = a.hadm_id) AS icu_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM cohort)
),

-- Step 3: Count noninvasive diagnostics (using labevents as a proxy)
lab_counts AS (
  SELECT hadm_id, COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY hadm_id
)

-- Final query
SELECT 
  ai.icu_stay,
  CASE 
    WHEN ai.los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN ai.los BETWEEN 5 AND 8 THEN '5-8 days'
    ELSE 'Outside range'
  END AS los_category,
  COUNT(ai.hadm_id) AS admission_count,
  AVG(lc.lab_count) AS mean_lab_count
FROM admissions_info ai
LEFT JOIN lab_counts lc ON ai.hadm_id = lc.hadm_id
GROUP BY ai.icu_stay, los_category
ORDER BY ai.icu_stay, los_category;