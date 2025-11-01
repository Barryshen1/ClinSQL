WITH 
-- Step 1: Identify eligible patients (men aged 76-86)
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 76 AND 86
),

-- Step 2: First hospital admission for eligible patients
first_admission AS (
  SELECT subject_id, hadm_id, admittime,  -- Include admittime here
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Step 3: Patients on DAPT during their first admission
dapt_patients AS (
  SELECT DISTINCT f.hadm_id
  FROM first_admission f
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON f.hadm_id = p.hadm_id
  WHERE f.admission_rank = 1 AND p.starttime <= f.admittime AND (p.stoptime >= f.admittime OR p.stoptime IS NULL)
  AND LOWER(p.drug) IN ('aspirin', 'clopidogrel', 'prasugrel', 'ticagrelor')
  GROUP BY f.hadm_id
  HAVING COUNT(DISTINCT LOWER(p.drug)) >= 2
),

-- Step 4: Calculate ICU LOS for DAPT patients
icu_los AS (
  SELECT i.stay_id, i.hadm_id, DATETIME_DIFF(i.outtime, i.intime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN dapt_patients d ON i.hadm_id = d.hadm_id
)

-- Final step: Average ICU LOS
SELECT AVG(los_days) AS avg_icu_los
FROM icu_los;