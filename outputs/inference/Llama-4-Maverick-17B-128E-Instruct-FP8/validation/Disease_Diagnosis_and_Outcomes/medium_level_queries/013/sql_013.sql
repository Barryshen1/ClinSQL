WITH 
-- Step 1: Filter patients based on age, gender, and heart failure diagnosis
hf_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 80 AND 90
    AND d.icd_code LIKE 'I50%'
    AND a.admittime IS NOT NULL
),

-- Step 2: Calculate LOS and time-to-death
patient_outcomes AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los,
    hospital_expire_flag,
    DATETIME_DIFF(deathtime, admittime, DAY) AS time_to_death
  FROM hf_patients
),

-- Step 3: Group by LOS categories and calculate mortality and median time-to-death
los_groups AS (
  SELECT 
    CASE 
      WHEN los BETWEEN 1 AND 3 THEN '1-3'
      WHEN los BETWEEN 4 AND 7 THEN '4-7'
      WHEN los >= 8 THEN '>=8'
      ELSE 'Other'
    END AS los_category,
    hospital_expire_flag,
    time_to_death
  FROM patient_outcomes
)

SELECT 
  los_category,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  (SUM(hospital_expire_flag) / COUNT(*)) * 100 AS mortality_percent,
  APPROX_QUANTILES(time_to_death, 100)[OFFSET(50)] AS median_time_to_death
FROM los_groups
WHERE los_category != 'Other'
GROUP BY los_category
ORDER BY los_category;