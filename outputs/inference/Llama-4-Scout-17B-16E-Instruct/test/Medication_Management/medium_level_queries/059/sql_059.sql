WITH 
-- Define medication classes
medication_classes AS (
  SELECT 
    itemid,
    label,
    CASE
      WHEN label LIKE '%metformin%' OR label LIKE '%sulfonylurea%' OR label LIKE '%pioglitazone%' OR label LIKE '%insulin%' THEN 'Antidiabetic'
      WHEN label LIKE '%beta blocker%' THEN 'Beta-blocker'
      WHEN label LIKE '%ACE inhibitor%' OR label LIKE '%ARB%' OR label LIKE '%ARNI%' THEN 'ACEi/ARB/ARNI'
      WHEN label LIKE '%loop diuretic%' THEN 'Loop diuretic'
      ELSE 'Other'
    END AS medication_class
  FROM 
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  UNION ALL
  SELECT 
    itemid,
    label,
    CASE
      WHEN label LIKE '%metformin%' OR label LIKE '%sulfonylurea%' OR label LIKE '%pioglitazone%' OR label LIKE '%insulin%' THEN 'Antidiabetic'
      WHEN label LIKE '%beta blocker%' THEN 'Beta-blocker'
      WHEN label LIKE '%ACE inhibitor%' OR label LIKE '%ARB%' OR label LIKE '%ARNI%' THEN 'ACEi/ARB/ARNI'
      WHEN label LIKE '%loop diuretic%' THEN 'Loop diuretic'
      ELSE 'Other'
    END AS medication_class
  FROM 
    `physionet-data.mimiciv_3_1_icu.d_items`
),

-- Identify eligible patients
eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.anchor_age BETWEEN 60 AND 70
    AND p.gender = 'F'
    AND a.dischtime IS NOT NULL
),

-- Identify T2DM and HF diagnoses
t2dm_diagnoses AS (
  SELECT 
    subject_id,
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code IN ('250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9')  -- T2DM
),

hf_diagnoses AS (
  SELECT 
    subject_id,
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9')  -- HF
),

-- Identify patients with both T2DM and HF
eligible_diagnoses AS (
  SELECT 
    t2dm.subject_id,
    t2dm.hadm_id
  FROM 
    t2dm_diagnoses t2dm
  INTERSECT DISTINCT
  SELECT 
    hf.subject_id,
    hf.hadm_id
  FROM 
    hf_diagnoses hf
),

-- Identify medication initiation
medication_initiation AS (
  SELECT 
    ed.subject_id,
    ed.hadm_id,
    mc.medication_class,
    pr.starttime
  FROM 
    eligible_diagnoses ed
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON 
    ed.hadm_id = pr.hadm_id
  JOIN 
    medication_classes mc
  ON 
    pr.drug = mc.label
)

-- Calculate initiation percentages and absolute differences
SELECT 
  medication_class,
  COUNT(CASE WHEN pr.starttime - a.admittime <= 48 * 3600 THEN 1 END) AS init_first_48h,
  COUNT(CASE WHEN a.dischtime - pr.starttime <= 24 * 3600 THEN 1 END) AS init_final_24h,
  COUNT(*) AS total_patients
FROM 
  medication_initiation pr
JOIN 
  eligible_patients a
ON 
  pr.hadm_id = a.hadm_id
GROUP BY 
  medication_class;