WITH 
-- Step 1: Filter patients
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 77 AND 87
),

-- Step 2: Relevant admissions with LOS
admissions_los AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
),

-- Step 3: Categorize admissions into ICU vs non-ICU
icu_status AS (
  SELECT a.hadm_id,
         CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM admissions_los a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),

-- Step 4: Count CT/MRI procedures
ct_mri_counts AS (
  SELECT p.hadm_id, COUNT(*) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON p.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%ct%' OR LOWER(d.label) LIKE '%mri%'
  GROUP BY p.hadm_id
)

-- Step 5: Final aggregation
SELECT 
  icu.icu_status,
  CASE 
    WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN a.los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_category,
  COUNT(*) AS num_admissions,
  AVG(ct_mri.ct_mri_count) AS mean_ct_mri,
  MIN(ct_mri.ct_mri_count) AS min_ct_mri,
  MAX(ct_mri.ct_mri_count) AS max_ct_mri
FROM icu_status icu
JOIN admissions_los a ON icu.hadm_id = a.hadm_id
LEFT JOIN ct_mri_counts ct_mri ON icu.hadm_id = ct_mri.hadm_id
WHERE a.los_days BETWEEN 1 AND 8
GROUP BY icu.icu_status, los_category
ORDER BY icu.icu_status, los_category;