WITH 
-- Step 1: Patient Selection
patients_selected AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
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
),

-- Step 2: Hemorrhagic Stroke Identification
hemorrhagic_stroke AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code LIKE '907.0'  -- ICD-9 code for hemorrhagic stroke
    OR icd_code LIKE 'I62%'  -- ICD-10 codes for hemorrhagic stroke
),

-- Step 3: Medication Complexity within first 48 hours
medication_complexity AS (
  SELECT 
    p.subject_id, 
    p.hadm_id,
    COUNT(DISTINCT m.drug) AS num_drugs
  FROM 
    patients_selected p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` m 
      ON p.hadm_id = m.hadm_id
  WHERE 
    m.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 48 HOUR)
  GROUP BY 
    p.subject_id, 
    p.hadm_id
),

-- Step 4: Identify serotonergic drugs
serotonergic_drugs AS (
  SELECT 
    subject_id, 
    hadm_id,
    COUNT(DISTINCT drug) AS num_serotonergic_drugs
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%fluoxetine%' 
    OR LOWER(drug) LIKE '%sertraline%' 
    OR LOWER(drug) LIKE '%paroxetine%' 
    OR LOWER(drug) LIKE '%citalopram%' 
    OR LOWER(drug) LIKE '%escitalopram%' 
    -- Add more serotonergic drugs as needed
  GROUP BY 
    subject_id, 
    hadm_id
),

-- Step 5: Calculate outcomes (LOS, Mortality)
outcomes AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    CASE 
      WHEN a.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS mortality
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
)

-- Final query combining all steps
SELECT 
  CASE 
    WHEN hs.hadm_id IS NOT NULL THEN 'Hemorrhagic Stroke'
    ELSE 'Controls'
  END AS group_category,
  mc.num_drugs,
  COALESCE(sd.num_serotonergic_drugs, 0) AS num_serotonergic_drugs,
  o.los_hours,
  o.mortality
FROM 
  patients_selected p
  LEFT JOIN hemorrhagic_stroke hs 
    ON p.hadm_id = hs.hadm_id
  JOIN medication_complexity mc 
    ON p.hadm_id = mc.hadm_id
  LEFT JOIN serotonergic_drugs sd 
    ON p.hadm_id = sd.hadm_id
  JOIN outcomes o 
    ON p.hadm_id = o.hadm_id;