WITH 
patients AS (
  SELECT 
    subject_id, 
    anchor_age, 
    dod,
    gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients`
),

admissions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime, 
    admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

icustays AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id, 
    intime, 
    outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),

diagnoses AS (
  SELECT 
    subject_id, 
    hadm_id, 
    icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),

labitems AS (
  SELECT 
    itemid, 
    label
  FROM 
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
),

medication AS (
  SELECT 
    subject_id, 
    hadm_id, 
    drug
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

-- Identify eligible patients
eligible_patients AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id
  FROM 
    admissions a
  JOIN 
    patients p 
  ON 
    a.subject_id = p.subject_id
  JOIN 
    diagnoses d 
  ON 
    a.hadm_id = d.hadm_id
  WHERE 
    p.anchor_age BETWEEN 57 AND 67
    AND p.gender = 'M'
    AND d.icd_code LIKE '%250%'  -- Diabetes
    AND d.icd_code LIKE '%428%'  -- Acute HF
),

-- Identify patients with GLP-1 in first 72h and last 24h
glp1_initiation AS (
  SELECT 
    e.hadm_id,
    CASE 
      WHEN TIMESTAMP_DIFF(a.admittime, e.starttime, HOUR) BETWEEN 0 AND 72 THEN 'first_72h'
      WHEN TIMESTAMP_DIFF(a.dischtime, e.stoptime, HOUR) BETWEEN 0 AND 24 THEN 'last_24h'
    END AS period
  FROM 
    admissions a
  JOIN 
    medication e 
  ON 
    a.hadm_id = e.hadm_id
  WHERE 
    e.drug LIKE '%GLP-1%' 
    AND a.hadm_id IN (SELECT hadm_id FROM eligible_patients)
),

-- Calculate initiation rates
initiation_rates AS (
  SELECT 
    period,
    COUNT(DISTINCT hadm_id) AS num_patients_with_glp1
  FROM 
    glp1_initiation
  GROUP BY 
    period
)

SELECT 
  first_72h.num_patients_with_glp1 AS first_72h_rate,
  last_24h.num_patients_with_glp1 AS last_24h_rate,
  last_24h.num_patients_with_glp1 - first_72h.num_patients_with_glp1 AS absolute_change,
  (last_24h.num_patients_with_glp1 - first_72h.num_patients_with_glp1) / first_72h.num_patients_with_glp1 * 100 AS relative_change
FROM 
  initiation_rates first_72h
  CROSS JOIN initiation_rates last_24h
WHERE 
  first_72h.period = 'first_72h'
  AND last_24h.period = 'last_24h';