WITH 
-- Step 1: Filter patients
patients AS (
  SELECT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 59 AND 69
),

-- Step 2: Identify admissions for these patients with PE diagnosis
admissions_pe AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients p ON a.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
    WHERE d.hadm_id = a.hadm_id AND dicd.long_title LIKE '%Pulmonary embolism%'
  )
),

-- Step 3: Calculate comorbidity score (simplified example, actual might require more complex scoring)
comorbidity AS (
  SELECT d.hadm_id, COUNT(DISTINCT d.icd_code) as comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN admissions_pe a ON d.hadm_id = a.hadm_id
  GROUP BY d.hadm_id
),

-- Step 4: Determine 30-day mortality and LOS
outcomes AS (
  SELECT a.hadm_id,
         CASE WHEN a.deathtime IS NOT NULL AND DATETIME_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30d,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM admissions_pe a
),

-- Step 5: Identify cardio/neurologic complications
complications AS (
  SELECT d.hadm_id,
         MAX(CASE WHEN dicd.long_title LIKE '%Cardiac%' OR dicd.long_title LIKE '%Neurologic%' THEN 1 ELSE 0 END) AS cardio_neuro_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  JOIN admissions_pe a ON d.hadm_id = a.hadm_id
  GROUP BY d.hadm_id
)

-- Final aggregation
SELECT 
  AVG(c.comorbidity_count) AS mean_comorbidity_score,
  AVG(o.mortality_30d) AS mortality_30d_rate,
  AVG(CASE WHEN o.los IS NOT NULL THEN o.los ELSE 0 END) AS mean_los,
  AVG(comp.cardio_neuro_complication) AS cardio_neuro_complication_rate
FROM admissions_pe a
JOIN comorbidity c ON a.hadm_id = c.hadm_id
JOIN outcomes o ON a.hadm_id = o.hadm_id
JOIN complications comp ON a.hadm_id = comp.hadm_id
WHERE c.comorbidity_count > (SELECT AVG(comorbidity_count) FROM comorbidity);  -- High comorbidity burden;