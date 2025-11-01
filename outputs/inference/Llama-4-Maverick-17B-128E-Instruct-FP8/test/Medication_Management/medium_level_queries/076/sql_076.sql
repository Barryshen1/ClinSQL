WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime - a.admittime >= INTERVAL 36 HOUR
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
      WHERE icd.long_title LIKE '%Diabetes mellitus%' 
    )
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
      WHERE icd.long_title LIKE '%Heart failure%' 
    )
),

-- Step 2: Identify patients with injectable GLP-1 receptor agonists
glp1_administration AS (
  SELECT c.subject_id, c.hadm_id, 
         MIN(TIMESTAMP_DIFF(em.charttime, c.admittime, HOUR)) AS first_glp1_hour,
         MAX(TIMESTAMP_DIFF(em.charttime, c.admittime, HOUR)) AS last_glp1_hour
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` em ON c.hadm_id = em.hadm_id
  WHERE REGEXP_CONTAINS(LOWER(em.medication), r'glp-1|liraglutide|semaglutide|dulaglutide|exenatide')
  GROUP BY c.subject_id, c.hadm_id
),

-- Step 3: Calculate the timing of GLP-1 administration relative to admission
glp1_timing AS (
  SELECT subject_id, hadm_id,
         CASE 
           WHEN first_glp1_hour <= 24 THEN 'First 24 hours'
           ELSE 'Not in first 24 hours'
         END AS first_glp1_timing,
         CASE 
           WHEN last_glp1_hour >= TIMESTAMP_DIFF(dischtime, admittime, HOUR) - 12 THEN 'Last 12 hours'
           ELSE 'Not in last 12 hours'
         END AS last_glp1_timing
  FROM glp1_administration
  JOIN cohort USING (subject_id, hadm_id)
)

-- Step 4: Calculate percentages
SELECT 
  IFNULL(SAFE_DIVIDE(COUNTIF(first_glp1_timing = 'First 24 hours'), COUNT(*)) * 100, 0) AS percent_first_24h,
  IFNULL(SAFE_DIVIDE(COUNTIF(last_glp1_timing = 'Last 12 hours'), COUNT(*)) * 100, 0) AS percent_last_12h
FROM glp1_timing;