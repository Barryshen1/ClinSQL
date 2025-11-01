WITH 
-- Step 1: Identify AKI admissions and patient info
aki_admissions AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    d.icd_code,
    d.icd_version,
    d.seq_num
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 43 AND 53
),

-- Step 2: Classify AKI as primary or secondary based on seq_num
aki_type_classification AS (
  SELECT 
    hadm_id,
    MIN(seq_num) AS min_seq_num,
    COUNT(*) AS num_aki_diagnoses
  FROM 
    aki_admissions
  WHERE 
    icd_code LIKE 'N17%'  -- Assuming N17 is the ICD code for AKI
  GROUP BY 
    hadm_id
),

-- Step 3: Calculate LOS and identify MRI/CT procedures
admission_details AS (
  SELECT 
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    COUNTIF(hc.hcpcs_cd IN ('72125', '72126', '72127', '72128', '72129', '72130', '72131', '72132', '72133', '72192', '72193', '72194', '70450', '70460', '70470', '70480', '70490', '70496', '70498')) AS num_mri_ct
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc ON a.hadm_id = hc.hadm_id
  GROUP BY 
    a.hadm_id, a.admittime, a.dischtime
),

-- Step 4: Combine data and calculate required metrics
combined_data AS (
  SELECT 
    ad.hadm_id,
    ad.los,
    ad.num_mri_ct,
    akit.min_seq_num,
    akit.num_aki_diagnoses
  FROM 
    admission_details ad
  INNER JOIN 
    aki_type_classification akit ON ad.hadm_id = akit.hadm_id
)

SELECT 
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'outside range'
  END AS los_category,
  CASE 
    WHEN min_seq_num = 1 THEN 'primary'
    ELSE 'secondary'
  END AS aki_type,
  COUNT(DISTINCT hadm_id) AS num_admissions,
  AVG(num_mri_ct) AS mean_mri_ct
FROM 
  combined_data
GROUP BY 
  los_category,
  aki_type
ORDER BY 
  los_category,
  aki_type;