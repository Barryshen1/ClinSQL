WITH 
-- Step 1: Identify patients with T2D and heart failure
diabetes_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Diabetes mellitus type 2%'
),
heart_failure_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Heart failure%'
),
target_patients AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 38 AND 48
  AND a.hadm_id IN (SELECT hadm_id FROM diabetes_patients)
  AND a.hadm_id IN (SELECT hadm_id FROM heart_failure_patients)
),

-- Step 2 & 3: Analyze medication initiation
medication_initiation AS (
  SELECT tp.hadm_id, 
         CASE 
           WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
           WHEN LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' THEN 'Oral Agents'
           ELSE 'Other'
         END AS medication_type,
         p.starttime,
         tp.admittime,
         tp.dischtime
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON tp.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN tp.admittime AND tp.dischtime
  AND (LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%')
),

-- Step 4: Calculate percentages
medication_timing AS (
  SELECT hadm_id, medication_type,
         CASE 
           WHEN starttime <= TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN 'First 72h'
           WHEN starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR) THEN 'Last 72h'
           ELSE 'In Between'
         END AS timing
  FROM medication_initiation
),
first_last_72h AS (
  SELECT medication_type, timing, COUNT(DISTINCT hadm_id) AS count_hadm_id
  FROM medication_timing
  WHERE timing IN ('First 72h', 'Last 72h')
  GROUP BY medication_type, timing
)

SELECT medication_type, timing, count_hadm_id,
       SUM(count_hadm_id) OVER (PARTITION BY timing) AS total_in_timing,
       ROUND(count_hadm_id / SUM(count_hadm_id) OVER (PARTITION BY timing) * 100, 2) AS percentage
FROM first_last_72h
ORDER BY medication_type, timing;