WITH 
age_filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 77 AND 87
),
admissions_filtered AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN age_filtered_patients p ON a.subject_id = p.subject_id
),
icu_status AS (
  SELECT a.hadm_id, 
         CASE 
           WHEN i.intime IS NOT NULL AND DATETIME_DIFF(i.intime, a.admittime, HOUR) BETWEEN 0 AND 24 THEN 'ICU'
           ELSE 'non-ICU'
         END AS icu_day1
  FROM admissions_filtered a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),
los_categorized AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
         CASE 
           WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
           WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
           ELSE '>=8'
         END AS los_category
  FROM admissions_filtered a
),
diagnoses AS (
  SELECT d.hadm_id, 
         MAX(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS hf,
         MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS ckd,
         MAX(CASE WHEN d.icd_code LIKE 'E1[0-4]%' THEN 1 ELSE 0 END) AS diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN admissions_filtered a ON d.hadm_id = a.hadm_id
  GROUP BY d.hadm_id
),
combined_data AS (
  SELECT 
    i.icu_day1,
    l.los_category,
    a.hospital_expire_flag,
    l.los_days,
    d.ckd,
    d.diabetes
  FROM icu_status i
  INNER JOIN los_categorized l ON i.hadm_id = l.hadm_id
  INNER JOIN admissions_filtered a ON i.hadm_id = a.hadm_id
  INNER JOIN diagnoses d ON i.hadm_id = d.hadm_id
  WHERE d.hf = 1
)
SELECT 
  icu_day1,
  los_category,
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) / COUNT(*) * 100 AS in_hospital_mortality,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  SUM(ckd) / COUNT(*) * 100 AS ckd_prevalence,
  SUM(diabetes) / COUNT(*) * 100 AS diabetes_prevalence
FROM combined_data
GROUP BY icu_day1, los_category
ORDER BY icu_day1, los_category;