WITH 
-- Define the medication classes of interest
medication_classes AS (
  SELECT 
    'antidiabetics' AS medication_class, 
    'metformin' AS medication_name
  UNION ALL
  SELECT 'antidiabetics', 'insulin'
  UNION ALL
  SELECT 'beta_blockers', 'atenolol'
  UNION ALL
  SELECT 'beta_blockers', 'metoprolol'
  UNION ALL
  SELECT 'acei_arb_arni', 'lisinopril'
  UNION ALL
  SELECT 'acei_arb_arni', 'losartan'
  UNION ALL
  SELECT 'loop_diuretics', 'furosemide'
),

-- Extract relevant patient information
patients_of_interest AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
),

-- Extract relevant medication information
medications AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    pc.drug,
    pc.starttime,
    pc.stoptime
  FROM 
    patients_of_interest p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pc
  ON 
    p.hadm_id = pc.hadm_id
  WHERE 
    pc.drug_type = 'medication'
),

-- Extract relevant diagnosis information
diagnoses AS (
  SELECT 
    subject_id,
    hadm_id,
    icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code IN (
      '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9', 
      '428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9'
    )
),

-- Identify patients with diabetes and heart failure
patients_with_conditions AS (
  SELECT 
    p.subject_id,
    p.hadm_id
  FROM 
    patients_of_interest p
  JOIN 
    diagnoses d
  ON 
    p.hadm_id = d.hadm_id
  WHERE 
    (d.icd_code IN ('250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9') 
     OR d.icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9'))
),

-- Identify medication initiation rates
medication_initiation AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    m.drug,
    m.starttime,
    CASE 
      WHEN m.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 48 HOUR) THEN 'first_48h'
      WHEN m.starttime BETWEEN TIMESTAMP_SUB(p.dischtime, INTERVAL 12 HOUR) AND p.dischtime THEN 'last_12h'
      ELSE 'other'
    END AS time_frame,
    mc.medication_class
  FROM 
    patients_with_conditions p
  JOIN 
    medications m
  ON 
    p.hadm_id = m.hadm_id
  JOIN 
    medication_classes mc
  ON 
    LOWER(m.drug) LIKE CONCAT('%', LOWER(mc.medication_name), '%')
)

-- Calculate initiation rates
SELECT 
  mi.time_frame,
  mi.medication_class,
  COUNT(DISTINCT mi.hadm_id) AS num_initiations
FROM 
  medication_initiation mi
GROUP BY 
  mi.time_frame, mi.medication_class
ORDER BY 
  mi.time_frame, mi.medication_class;