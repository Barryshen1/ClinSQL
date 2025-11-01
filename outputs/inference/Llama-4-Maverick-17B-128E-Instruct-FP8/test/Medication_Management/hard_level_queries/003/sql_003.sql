WITH 
-- Step 1: Identify the cohort (male inpatients aged 39-49)
cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 39 AND 49
),

-- Step 2: Identify hospital admissions for the cohort
admissions_cohort AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort c ON a.subject_id = c.subject_id
),

-- Step 3: Identify hospital admissions for status epilepticus
status_epilepticus_admissions AS (
  SELECT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Status epilepticus%'
),

-- Step 4: Patients in ICU within the first 24 hours who are in the cohort and have status epilepticus
icu_stays AS (
  SELECT i.stay_id, i.hadm_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN admissions_cohort ac ON i.hadm_id = ac.hadm_id
  WHERE i.hadm_id IN (SELECT hadm_id FROM status_epilepticus_admissions)
),

-- Step 5: Medication prescriptions within the first 24 hours of ICU stay
icu_medications AS (
  SELECT i.stay_id, p.drug, p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN icu_stays i ON p.hadm_id = i.hadm_id
  WHERE p.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
),

-- Step 6: Identify QT-prolonging and bleeding-risk medications (simplified, actual implementation depends on specific medication lists)
medication_risks AS (
  SELECT stay_id, drug,
         CASE WHEN drug LIKE '%QT-prolonging%' THEN 'QT-prolonging'
              WHEN drug LIKE '%bleeding-risk%' THEN 'Bleeding-risk'
              ELSE 'Other'
         END AS risk_category
  FROM icu_medications
),

-- Step 7: Calculate medication complexity (count of medications per stay_id)
medication_complexity AS (
  SELECT stay_id, COUNT(DISTINCT drug) AS num_medications
  FROM icu_medications
  GROUP BY stay_id
),

-- Step 8: Calculate percentile rank for medication complexity
percentile_rank AS (
  SELECT stay_id, num_medications,
         PERCENT_RANK() OVER (ORDER BY num_medications) AS percentile
  FROM medication_complexity
),

-- Step 9: Calculate LOS and Mortality
los_mortality AS (
  SELECT i.stay_id, i.los, 
         CASE WHEN a.dischtime IS NULL OR a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS hospital_mortality
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
)

-- Final query to compare metrics and report for target top quartile
SELECT 
  risk_category,
  PERCENTILE_CONT(num_medications, 0.75) OVER () AS top_quartile_medication_complexity,
  AVG(los) AS avg_los,
  AVG(hospital_mortality) AS avg_hospital_mortality
FROM (
  SELECT m.risk_category, mc.num_medications, lm.los, lm.hospital_mortality
  FROM medication_risks m
  JOIN medication_complexity mc ON m.stay_id = mc.stay_id
  JOIN percentile_rank pr ON mc.stay_id = pr.stay_id
  JOIN los_mortality lm ON pr.stay_id = lm.stay_id
  WHERE pr.percentile >= 0.75  -- Top quartile
)
GROUP BY risk_category;