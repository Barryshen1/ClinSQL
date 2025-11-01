WITH patient_data AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    d.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND d.icd_code IN (
      '481',  -- Pneumonia
      '491',  -- COPD
      '492',  -- COPD with acute exacerbation
      '493',  -- COPD with acute exacerbation, unspecified
      'J18',  -- Pneumonia, unspecified organism
      'J18.0', 'J18.1', 'J18.8', 'J18.9',  -- Pneumonia, organism not specified
      'J44',  -- Chronic obstructive pulmonary disease
      'J44.0', 'J44.1', 'J44.8', 'J44.9'  -- COPD and related conditions
    )
),
los_data AS (
  SELECT 
    subject_id,
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM 
    patient_data
)
SELECT 
  APPROX_QUANTILES(los, 0.75)[OFFSET(1)] AS percentile_75_los
FROM 
  los_data;