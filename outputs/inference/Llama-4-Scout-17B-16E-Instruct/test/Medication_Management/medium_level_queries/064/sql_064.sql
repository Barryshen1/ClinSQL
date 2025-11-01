WITH 
-- Define medication classes
medication_classes AS (
  SELECT 
    'metformin' AS medication_class,
    'Metformin' AS medication_name
  UNION ALL
  SELECT 
    'sulfonylureas', 
    'Glyburide' 
  UNION ALL
  SELECT 
    'sulfonylureas', 
    'Gliclazide' 
  UNION ALL
  SELECT 
    'DPP-4', 
    'Sitagliptin' 
  UNION ALL
  SELECT 
    'SGLT2', 
    'Canagliflozin' 
  UNION ALL
  SELECT 
    'thiazolidinediones', 
    'Pioglitazone'
),

-- Identify patients with diabetes and acute heart failure
target_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 71 AND 81
    AND a.subject_id IN (
      SELECT 
        subject_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN (
          -- Diabetes
          '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9',
          'E10.0', 'E10.1', 'E10.2', 'E10.3', 'E10.4', 'E10.5', 'E10.6', 'E10.7', 'E10.8', 'E10.9',
          -- Acute heart failure
          '428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9',
          'I50.0', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.5', 'I50.6', 'I50.7', 'I50.8', 'I50.9'
        )
    )
),

-- Identify medication orders
medication_orders AS (
  SELECT 
    p.hadm_id,
    p.subject_id,
    p.starttime,
    mc.medication_class
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN 
    medication_classes mc
  ON 
    LOWER(p.drug) LIKE LOWER(mc.medication_name)
)

-- Calculate initiation rates
SELECT 
  mo.medication_class,
  COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(mo.starttime, tp.admittime, SECOND) <= 72 * 3600 THEN mo.hadm_id END) AS first_72h_initiations,
  COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(mo.starttime, tp.admittime, SECOND) >= TIMESTAMP_DIFF(tp.dischtime, tp.admittime, SECOND) - 48 * 3600 THEN mo.hadm_id END) AS last_48h_initiations,
  COUNT(DISTINCT mo.hadm_id) AS total_initiations
FROM 
  medication_orders mo
JOIN 
  target_patients tp
ON 
  mo.hadm_id = tp.hadm_id
GROUP BY 
  mo.medication_class;