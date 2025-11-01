WITH 
-- Step 1: Identify relevant ICD codes for hemorrhagic stroke
hemorrhagic_stroke_icd_codes AS (
  SELECT icd_code 
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE lower(long_title) LIKE '%hemorrhagic stroke%' OR lower(long_title) LIKE '%intracerebral hemorrhage%'
),

-- Step 2: Filter admissions for females aged 37-47 with primary hemorrhagic stroke
relevant_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code IN (SELECT icd_code FROM hemorrhagic_stroke_icd_codes) 
      AND seq_num = 1  -- Primary diagnosis
    )
)

-- Step 3 & 4: Calculate hospital LOS and its 75th percentile
SELECT 
  APPROX_QUANTILES(DATE_DIFF(dischtime, admittime, DAY), 100)[OFFSET(75)] AS los_75th_percentile
FROM 
  relevant_admissions;