WITH 
-- Step 1: Identify patients with AKI and their admission details
aki_patients AS (
  SELECT DISTINCT 
    diag.subject_id, 
    diag.hadm_id,
    CASE 
      WHEN diag.seq_num = (SELECT MIN(seq_num) FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 WHERE d2.hadm_id = diag.hadm_id) THEN 'Primary'
      ELSE 'Secondary'
    END AS aki_diagnosis_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE 
    LOWER(d_diag.long_title) LIKE '%acute kidney%'  
),

-- Step 2: Count diagnostic imaging studies per admission
imaging_studies AS (
  SELECT 
    hcpcs.hadm_id, 
    COUNT(*) AS num_imaging_studies
  FROM 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpcs
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d_hcpcs ON hcpcs.hcpcs_cd = d_hcpcs.code
  WHERE 
    d_hcpcs.category IN ( -- Example categories; actual values should be verified
      -- Add the relevant category codes or values here, e.g., 
      -- 'Diagnostic Imaging', '2' if it's coded as such
    )
    -- Alternatively, if category is not directly usable, filter based on hcpcs_cd
    -- OR hcpcs.hcpcs_cd LIKE '%some relevant code%'
  GROUP BY 
    hcpcs.hadm_id
),

-- Step 3: Calculate LOS and filter patients
patient_data AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    aki.aki_diagnosis_type,
    COALESCE(img.num_imaging_studies, 0) AS num_imaging_studies
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN 
    aki_patients aki ON a.hadm_id = aki.hadm_id
  LEFT JOIN 
    imaging_studies img ON a.hadm_id = img.hadm_id
  WHERE 
    p.gender = 'F' AND 
    p.anchor_age BETWEEN 64 AND 74
),

-- Step 4: Filter by LOS and calculate median (IQR) of imaging studies
filtered_data AS (
  SELECT 
    aki_diagnosis_type,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Outside Range'
    END AS los_category,
    num_imaging_studies
  FROM 
    patient_data
  WHERE 
    los_days BETWEEN 1 AND 7
)

SELECT 
  aki_diagnosis_type,
  los_category,
  APPROX_QUANTILES(num_imaging_studies, 100)[OFFSET(50)] AS median_imaging_studies,
  APPROX_QUANTILES(num_imaging_studies, 100)[OFFSET(25)] AS q1_imaging_studies,
  APPROX_QUANTILES(num_imaging_studies, 100)[OFFSET(75)] AS q3_imaging_studies
FROM 
  filtered_data
GROUP BY 
  aki_diagnosis_type, 
  los_category
ORDER BY 
  aki_diagnosis_type, 
  los_category;