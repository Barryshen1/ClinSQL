WITH 
-- Filter patients based on age and gender
filtered_patients AS (
  SELECT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 71 AND 81
),

-- Identify patients with diabetes and acute heart failure
diabetes_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE lower(long_title) LIKE '%diabetes%')
),
heart_failure_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE lower(long_title) LIKE '%heart failure%')
),

-- Get admission and discharge times
admission_times AS (
  SELECT hadm_id, admittime AS adm_time, dischtime AS discharge_time
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Classify medications
medication_classification AS (
  SELECT 
    hadm_id,
    starttime,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%sulfonylurea%' THEN 'Sulfonylureas'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      ELSE NULL
    END AS medication_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug_type = 'MAIN'
),

-- Calculate initiation rates for the first 72 hours and last 48 hours
medication_initiation AS (
  SELECT 
    fp.hadm_id,
    at.adm_time,
    at.discharge_time,
    mc.medication_class,
    CASE 
      WHEN mc.starttime BETWEEN at.adm_time AND TIMESTAMP_ADD(at.adm_time, INTERVAL 72 HOUR) THEN 'First 72h'
      WHEN mc.starttime BETWEEN TIMESTAMP_SUB(at.discharge_time, INTERVAL 48 HOUR) AND at.discharge_time THEN 'Last 48h'
      ELSE 'Other'
    END AS time_frame
  FROM filtered_patients fp
  JOIN diabetes_patients dp ON fp.hadm_id = dp.hadm_id
  JOIN heart_failure_patients hfp ON fp.hadm_id = hfp.hadm_id
  JOIN admission_times at ON fp.hadm_id = at.hadm_id
  LEFT JOIN medication_classification mc ON fp.hadm_id = mc.hadm_id
  WHERE mc.medication_class IS NOT NULL
)

-- Calculate and report initiation rates
SELECT 
  medication_class,
  time_frame,
  COUNT(DISTINCT hadm_id) AS num_initiated,
  COUNT(DISTINCT hadm_id) / (SELECT COUNT(DISTINCT fp.hadm_id) FROM filtered_patients fp JOIN diabetes_patients dp ON fp.hadm_id = dp.hadm_id JOIN heart_failure_patients hfp ON fp.hadm_id = hfp.hadm_id) * 100 AS initiation_rate_percent
FROM medication_initiation
WHERE time_frame IN ('First 72h', 'Last 48h')
GROUP BY medication_class, time_frame
ORDER BY medication_class, time_frame;