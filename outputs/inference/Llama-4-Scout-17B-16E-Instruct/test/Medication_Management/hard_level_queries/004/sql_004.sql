WITH 
-- Identify acute ischemic stroke patients
stroke_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id 
      AND d.icd_code LIKE '433%'  -- Acute ischemic stroke ICD code
    )
),

-- Identify patients with CYP3A4 interactions affecting NTI drugs
cyp3a4_interactions AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE 
    -- Simplified example for drugs with known CYP3A4 interactions and NTI
    drug LIKE '%NTI%'  -- Placeholder for specific NTI drugs
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` l
      JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
        ON l.itemid = le.itemid
      WHERE le.hadm_id = p.hadm_id 
      AND l.label LIKE '%CYP3A4%'  -- Placeholder for CYP3A4 interaction lab
    )
),

-- Calculate outcomes
outcomes AS (
  SELECT 
    sp.subject_id,
    sp.hadm_id,
    icu.stay_id,
    icu.los AS icu_los,
    a.dischtime - a.admittime AS hospital_los,
    CASE 
      WHEN p.dod IS NOT NULL THEN 1 
      ELSE 0 
    END AS mortality
  FROM 
    stroke_patients sp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON sp.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON sp.hadm_id = icu.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON sp.subject_id = p.subject_id
)

-- Final query
SELECT 
  COALESCE(ci.hadm_id, op.hadm_id) AS hadm_id,
  op.icu_los,
  op.hospital_los,
  op.mortality
FROM 
  outcomes op
  LEFT JOIN cyp3a4_interactions ci 
    ON op.hadm_id = ci.hadm_id
WHERE 
  op.mortality = 1  -- Focus on mortality for simplicity
ORDER BY 
  op.hospital_los DESC;