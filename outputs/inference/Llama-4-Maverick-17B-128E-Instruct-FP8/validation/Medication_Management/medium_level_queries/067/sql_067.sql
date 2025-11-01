WITH 
-- Step 1: Identify patients with diabetes and acute HF
diabetes_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON h.subject_id = diag.subject_id AND h.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON h.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 64 AND 74
  AND (d_diag.long_title LIKE '%Diabetes%' OR d_diag.long_title LIKE '%Heart Failure%')
),

-- Step 2: Extract relevant medication data
medications AS (
  SELECT DISTINCT p.hadm_id, p.drug, p.starttime, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN diabetes_patients d ON p.subject_id = d.subject_id AND p.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.hadm_id = a.hadm_id
  WHERE p.drug_type = 'MAIN' 
  AND (LOWER(p.drug) LIKE '%insulin%' 
       OR LOWER(p.drug) LIKE '%metformin%' 
       OR LOWER(p.drug) LIKE '%sulfonylurea%' 
       OR LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%'  -- DPP-4
       OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%'  -- SGLT2
       OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%dulaglutide%'  -- GLP-1
       OR LOWER(p.drug) LIKE '%pioglitazone%'  -- TZDs
      )
),

-- Step 3: Classify medications and determine initiation within time frames
med_classification AS (
  SELECT hadm_id,
         CASE 
           WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
           WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
           WHEN LOWER(drug) LIKE '%sulfonylurea%' THEN 'Sulfonylureas'
           WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4'
           WHEN LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' THEN 'SGLT2'
           WHEN LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%dulaglutide%' THEN 'GLP-1'
           WHEN LOWER(drug) LIKE '%pioglitazone%' THEN 'TZDs'
           ELSE 'Other'
         END AS med_class,
         CASE 
           WHEN starttime <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 'First 12h'
           WHEN starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) THEN 'Last 48h'
           ELSE 'Other'
         END AS time_frame
  FROM medications
),

-- Step 4: Calculate percentages
initiation_percentages AS (
  SELECT med_class, time_frame, COUNT(DISTINCT hadm_id) AS num_patients
  FROM med_classification
  WHERE time_frame IN ('First 12h', 'Last 48h')
  GROUP BY med_class, time_frame
),

total_patients AS (
  SELECT time_frame, COUNT(DISTINCT hadm_id) AS total_hadm_ids
  FROM med_classification
  WHERE time_frame IN ('First 12h', 'Last 48h')
  GROUP BY time_frame
)

SELECT 
  i.med_class, 
  i.time_frame, 
  i.num_patients, 
  t.total_hadm_ids, 
  (i.num_patients / t.total_hadm_ids) * 100 AS percentage
FROM initiation_percentages i
JOIN total_patients t ON i.time_frame = t.time_frame
ORDER BY med_class, time_frame;