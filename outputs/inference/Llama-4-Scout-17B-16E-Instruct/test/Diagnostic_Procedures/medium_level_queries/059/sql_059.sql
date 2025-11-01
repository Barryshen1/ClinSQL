WITH 
-- Identify heart failure admissions
heart_failure_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    CASE 
      WHEN a.admission_type = 'elective' THEN 'primary'
      ELSE 'secondary'
    END AS hf_type,
    EXTRACT(DAY FROM a.dischtime - a.admittime) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 67 AND 77
    AND p.gender = 'M'
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN ('428', '428.0', '428.1', '428.2', '428.3', '428.4', '428.9')  -- ICD-9 codes for heart failure
        OR icd_code IN ('I50', 'I50.0', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.8', 'I50.9')  -- ICD-10 codes for heart failure
    )
),

-- Identify imaging studies
imaging_studies AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_imaging_studies
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    icd_code LIKE '87%'  -- Example ICD-9 codes for imaging, adjust as needed
    OR icd_code IN ('3E', '3F')  -- Example ICD-10 PCS codes for imaging, adjust as needed
  GROUP BY 
    hadm_id
),

-- Join heart failure admissions with imaging studies
heart_failure_imaging AS (
  SELECT 
    hfa.hadm_id,
    hfa.subject_id,
    hfa.anchor_age,
    hfa.gender,
    hfa.hf_type,
    hfa.los,
    COALESCE(imaging_studies.num_imaging_studies, 0) AS num_imaging_studies
  FROM 
    heart_failure_admissions hfa
  LEFT JOIN 
    imaging_studies 
      ON hfa.hadm_id = imaging_studies.hadm_id
)

-- Group by LOS categories and HF type, calculate percentiles of imaging studies
SELECT 
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_category,
  hf_type,
  APPROX_QUANTILES(num_imaging_studies, 0.25)[OFFSET(0)] AS p25,
  APPROX_QUANTILES(num_imaging_studies, 0.5)[OFFSET(0)] AS p50,
  APPROX_QUANTILES(num_imaging_studies, 0.75)[OFFSET(0)] AS p75
FROM 
  heart_failure_imaging
GROUP BY 
  los_category,
  hf_type;