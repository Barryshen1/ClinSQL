WITH 
-- Step 1: Filter patients based on age, gender, diagnoses, and LOS
patients AS (
  SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id, icu.stay_id, 
         icu.intime, icu.outtime, DATETIME_DIFF(icu.outtime, icu.intime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 39 AND 49
    AND DATETIME_DIFF(icu.outtime, icu.intime, HOUR) >= 72
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.subject_id = p.subject_id AND d.hadm_id = a.hadm_id
        AND (dicd.long_title LIKE '%Type 2 diabetes mellitus%' OR dicd.long_title LIKE '%Heart failure%')
    )
),

-- Step 2: Identify insulin administrations
insulin_administrations AS (
  SELECT i.subject_id, i.stay_id, i.starttime, i.itemid, di.label
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  WHERE di.label LIKE '%Insulin%' 
),

-- Step 3: Classify insulin therapy types for each patient stay
insulin_therapy AS (
  SELECT it.stay_id, it.starttime,
         CASE
           WHEN di.label LIKE '%Basal%' THEN 'Basal'
           WHEN di.label LIKE '%Bolus%' THEN 'Bolus'
           WHEN di.label LIKE '%Sliding%' THEN 'Sliding-scale'
           ELSE 'Other'
         END AS therapy_type
  FROM insulin_administrations it
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON it.itemid = di.itemid
  JOIN patients p ON it.stay_id = p.stay_id
  WHERE it.starttime BETWEEN p.intime AND p.outtime
),

-- Step 4: Analyze insulin therapy in the first 72 hours and final 48 hours
therapy_analysis AS (
  SELECT it.stay_id,
         COUNT(DISTINCT CASE WHEN it.starttime <= p.intime + INTERVAL 72 HOUR THEN it.therapy_type END) AS therapy_types_first_72h,
         COUNT(DISTINCT CASE WHEN it.starttime >= p.outtime - INTERVAL 48 HOUR THEN it.therapy_type END) AS therapy_types_last_48h
  FROM insulin_therapy it
  JOIN patients p ON it.stay_id = p.stay_id
  GROUP BY it.stay_id
),

-- Step 5: Calculate percentages and differences
therapy_counts AS (
  SELECT stay_id,
         MAX(CASE WHEN therapy_type = 'Basal' THEN 1 ELSE 0 END) AS Basal,
         MAX(CASE WHEN therapy_type = 'Bolus' THEN 1 ELSE 0 END) AS Bolus,
         MAX(CASE WHEN therapy_type = 'Sliding-scale' THEN 1 ELSE 0 END) AS Sliding_scale
  FROM insulin_therapy
  GROUP BY stay_id
)

SELECT 
  'Basal' AS therapy_type,
  COUNT(CASE WHEN Basal = 1 THEN 1 END) / COUNT(*) * 100 AS percent_total,
  COUNT(CASE WHEN Basal = 1 AND therapy_types_first_72h > 0 THEN 1 END) / COUNT(*) * 100 AS percent_first_72h,
  COUNT(CASE WHEN Basal = 1 AND therapy_types_last_48h > 0 THEN 1 END) / COUNT(*) * 100 AS percent_last_48h,
  (COUNT(CASE WHEN Basal = 1 AND therapy_types_last_48h > 0 THEN 1 END) / COUNT(*) * 100) - 
  (COUNT(CASE WHEN Basal = 1 AND therapy_types_first_72h > 0 THEN 1 END) / COUNT(*) * 100) AS percentage_point_diff
FROM therapy_counts
JOIN therapy_analysis ON therapy_counts.stay_id = therapy_analysis.stay_id
UNION ALL
SELECT 
  'Bolus',
  COUNT(CASE WHEN Bolus = 1 THEN 1 END) / COUNT(*) * 100,
  COUNT(CASE WHEN Bolus = 1 AND therapy_types_first_72h > 0 THEN 1 END) / COUNT(*) * 100,
  COUNT(CASE WHEN Bolus = 1 AND therapy_types_last_48h > 0 THEN 1 END) / COUNT(*) * 100,
  (COUNT(CASE WHEN Bolus = 1 AND therapy_types_last_48h > 0 THEN 1 END) / COUNT(*) * 100) - 
  (COUNT(CASE WHEN Bolus = 1 AND therapy_types_first_72h > 0 THEN 1 END) / COUNT(*) * 100)
FROM therapy_counts
JOIN therapy_analysis ON therapy_counts.stay_id = therapy_analysis.stay_id
UNION ALL
SELECT 
  'Sliding-scale',
  COUNT(CASE WHEN Sliding_scale = 1 THEN 1 END) / COUNT(*) * 100,
  COUNT(CASE WHEN Sliding_scale = 1 AND therapy_types_first_72h > 0 THEN 1 END) / COUNT(*) * 100,
  COUNT(CASE WHEN Sliding_scale = 1 AND therapy_types_last_48h > 0 THEN 1 END) / COUNT(*) * 100,
  (COUNT(CASE WHEN Sliding_scale = 1 AND therapy_types_last_48h > 0 THEN 1 END) / COUNT(*) * 100) - 
  (COUNT(CASE WHEN Sliding_scale = 1 AND therapy_types_first_72h > 0 THEN 1 END) / COUNT(*) * 100)
FROM therapy_counts
JOIN therapy_analysis ON therapy_counts.stay_id = therapy_analysis.stay_id;