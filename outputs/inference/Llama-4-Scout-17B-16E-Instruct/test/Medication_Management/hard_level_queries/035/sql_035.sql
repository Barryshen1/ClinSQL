WITH 
-- Identify female patients aged 40-50
eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE 
    p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
),

-- Identify admissions for eligible patients
eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN 
    eligible_patients p ON a.subject_id = p.subject_id
),

-- Assume a way to identify neutropenic fever (e.g., specific ICD codes or lab values)
neutropenic_fever_admissions AS (
  SELECT 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE 
    -- Example condition: ICD code for neutropenic fever
    icd_code LIKE 'D70%'
),

-- Calculate medication complexity score (example: count of distinct medications)
medication_complexity AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT drug) AS medication_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.prescriptions
  GROUP BY 
    hadm_id
),

-- Derive admission outcomes
admission_outcomes AS (
  SELECT 
    ea.hadm_id,
    TIMESTAMPDIFF(DAY, ea.admittime, ea.dischtime) AS los,
    IF(ea.deathtime IS NOT NULL, 1, 0) AS mortality,
    -- Example logic for 30-day readmission
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp`.admissions a2
        WHERE a2.subject_id = ea.subject_id 
          AND a2.admittime BETWEEN TIMESTAMP_ADD(ea.dischtime, INTERVAL 1 DAY) 
                                 AND TIMESTAMP_ADD(ea.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted
  FROM 
    eligible_admissions ea
),

-- Combine data and stratify by medication complexity score quartiles
quartile_data AS (
  SELECT 
    mc.hadm_id,
    mc.medication_count,
    ao.los,
    ao.mortality,
    ao.readmitted,
    NTILE(4) OVER (ORDER BY mc.medication_count) AS quartile
  FROM 
    medication_complexity mc
  JOIN 
    admission_outcomes ao ON mc.hadm_id = ao.hadm_id
  JOIN 
    neutropenic_fever_admissions nf ON mc.hadm_id = nf.hadm_id
)

SELECT 
  quartile,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(medication_count) AS mean_score,
  MIN(medication_count) AS min_score,
  MAX(medication_count) AS max_score,
  AVG(los) AS mean_los,
  AVG(mortality) AS mortality_rate,
  AVG(readmitted) AS readmission_rate
FROM 
  quartile_data
GROUP BY 
  quartile
ORDER BY 
  quartile;