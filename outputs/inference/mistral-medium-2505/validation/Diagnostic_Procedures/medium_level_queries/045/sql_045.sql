WITH
-- Get female patients aged 78-88
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 78 AND 88
),

-- Get admissions with DVT diagnosis
dvt_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE (d.icd_code LIKE '453.4%' OR d.icd_code LIKE 'I82.%')
),

-- Identify admissions with ICU stays
icu_admissions AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Count distinct lab tests per admission
lab_counts AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT itemid) AS lab_test_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN dvt_admissions a ON l.hadm_id = a.hadm_id
  GROUP BY a.hadm_id
)

-- Final aggregation
SELECT
  CASE
    WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN a.los_days BETWEEN 5 AND 8 THEN '5-8 days'
    ELSE 'Other'
  END AS los_category,
  CASE
    WHEN a.hadm_id IN (SELECT hadm_id FROM icu_admissions) THEN 'ICU'
    ELSE 'No ICU'
  END AS icu_status,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(l.lab_test_count) AS avg_lab_tests_per_admission
FROM dvt_admissions a
LEFT JOIN lab_counts l ON a.hadm_id = l.hadm_id
WHERE a.los_days BETWEEN 1 AND 8
GROUP BY los_category, icu_status
ORDER BY los_category, icu_status;