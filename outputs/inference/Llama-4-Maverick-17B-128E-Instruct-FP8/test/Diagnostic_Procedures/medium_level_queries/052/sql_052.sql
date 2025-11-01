WITH 
-- Step 1: Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 73 AND 83
),

-- Step 2: Identify relevant admissions and ICU stays
admissions AS (
  SELECT a.hadm_id, a.admission_type, 
         DATETIME_DIFF(ic.outtime, ic.intime, DAY) AS icu_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Step 3: Identify ultrasounds (including echocardiography)
ultrasound_counts AS (
  SELECT pe.hadm_id, COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ultrasound%' OR LOWER(di.label) LIKE '%echocardiography%'
  GROUP BY pe.hadm_id
)

-- Step 4: Aggregate results by admission type and ICU LOS
SELECT 
  a.admission_type,
  CASE 
    WHEN a.icu_los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN a.icu_los_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Outside range'
  END AS icu_los_category,
  COUNT(*) AS num_admissions,
  AVG(uc.ultrasound_count) AS mean_ultrasounds,
  MIN(uc.ultrasound_count) AS min_ultrasounds,
  MAX(uc.ultrasound_count) AS max_ultrasounds
FROM admissions a
JOIN ultrasound_counts uc ON a.hadm_id = uc.hadm_id
WHERE a.admission_type IN ('ELECTIVE', 'EMERGENCY')
GROUP BY a.admission_type, icu_los_category
ORDER BY a.admission_type, icu_los_category;