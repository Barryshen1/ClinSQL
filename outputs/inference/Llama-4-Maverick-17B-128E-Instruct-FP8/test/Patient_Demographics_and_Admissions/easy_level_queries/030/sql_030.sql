WITH 
-- Step 1: Identify female patients between 52 and 62 years old
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 52 AND 62
),

-- Step 2: Identify patients who received anticoagulants
anticoagulant_patients AS (
  SELECT DISTINCT p.subject_id
  FROM eligible_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  WHERE LOWER(pr.drug) LIKE '%heparin%' OR LOWER(pr.drug) LIKE '%warfarin%' 
     OR LOWER(pr.drug) LIKE '%apixaban%' OR LOWER(pr.drug) LIKE '%rivaroxaban%' 
     OR LOWER(pr.drug) LIKE '%dabigatran%' OR LOWER(pr.drug) LIKE '%edoxaban%'
),

-- Step 3: Get the first admission for these patients
first_admission_times AS (
  SELECT subject_id, MIN(admittime) AS first_admit_time
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE subject_id IN (SELECT subject_id FROM anticoagulant_patients)
  GROUP BY subject_id
),

-- Step 4: Get admission details for the first admissions and calculate LOS
first_admissions AS (
  SELECT a.subject_id, a.hadm_id, 
         a.admittime, a.dischtime,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN first_admission_times fat
    ON a.subject_id = fat.subject_id AND a.admittime = fat.first_admit_time
)

-- Step 5: Calculate the SD of LOS
SELECT STDDEV(los_days) AS sd_los
FROM first_admissions;