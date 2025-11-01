WITH cohort AS (
  -- Females aged 86-96 with DM and HF
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.hadm_id IN (
      -- DM diagnosis
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.icd_code LIKE 'E1%' -- ICD-10 DM codes
        AND di.icd_version = 10
      INTERSECT DISTINCT
      -- HF diagnosis
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.icd_code LIKE 'I50%' -- ICD-10 HF
        AND di.icd_version = 10
    )
),

meds AS (
  -- Get prescriptions and classify
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    -- Classify drug
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      ELSE 'Oral Agents'
    END AS drug_class,

    p.starttime,

    -- Check if in early window (first 12h)
    CASE 
      WHEN p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) 
        THEN 1 
      ELSE 0 
    END AS early_flag,

    -- Check if in late window (last 72h)
    CASE 
      WHEN p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime 
        THEN 1 
      ELSE 0 
    END AS late_flag

  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE 
    -- Only consider diabetes-related drugs (simplified filter)
    (LOWER(p.drug) LIKE '%insulin%' 
      OR LOWER(p.drug) LIKE '%metformin%'
      OR LOWER(p.drug) LIKE '%glipizide%'
      OR LOWER(p.drug) LIKE '%glyburide%'
      OR LOWER(p.drug) LIKE '%glimepiride%'
      OR LOWER(p.drug) LIKE '%pioglitazone%'
      OR LOWER(p.drug) LIKE '%sitagliptin%'
      OR LOWER(p.drug) LIKE '%saxagliptin%'
      OR LOWER(p.drug) LIKE '%linagliptin%'
      OR LOWER(p.drug) LIKE '%empagliflozin%'
      OR LOWER(p.drug) LIKE '%canagliflozin%'
      OR LOWER(p.drug) LIKE '%dapagliflozin%'
      OR LOWER(p.drug) LIKE '%semaglutide%'
      OR LOWER(p.drug) LIKE '%liraglutide%'
      OR LOWER(p.drug) LIKE '%exenatide%'
    )
),

-- For each patient and class, aggregate flags
patient_class_flags AS (
  SELECT 
    subject_id,
    hadm_id,
    drug_class,
    MAX(early_flag) AS early,   -- 1 if any early prescription in class
    MAX(late_flag) AS late      -- 1 if any late prescription in class
  FROM meds
  GROUP BY subject_id, hadm_id, drug_class
)

-- Final aggregation: count patients per class and transition
SELECT 
  drug_class,
  COUNT(*) AS total_patients,
  SUM(early) AS early_count,
  ROUND(100 * SUM(early) / COUNT(*), 1) AS early_rate_percent,
  SUM(late) AS late_count,
  ROUND(100 * SUM(late) / COUNT(*), 1) AS late_rate_percent,
  SUM(CASE WHEN early = 1 AND late = 1 THEN 1 ELSE 0 END) AS early_to_late_count,
  ROUND(100 * SUM(CASE WHEN early = 1 AND late = 1 THEN 1 ELSE 0 END) / SUM(early), 1) AS early_to_late_percent
FROM patient_class_flags
GROUP BY drug_class
ORDER BY drug_class;