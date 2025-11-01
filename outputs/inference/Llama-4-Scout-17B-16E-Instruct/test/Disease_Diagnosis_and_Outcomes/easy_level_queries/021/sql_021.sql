WITH 
  -- Filter patients
  filtered_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      EXTRACT(EPOCH FROM (a.dischtime - a.admittime)) / 24 AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 58 AND 68
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code IN ('430', '491.21')
      )
  )
  
SELECT 
  APPROX_QUANTILES(los_days, 100)[1] AS q1,
  APPROX_QUANTILES(los_days, 100)[2] AS median,
  APPROX_QUANTILES(los_days, 100)[4] AS q3,
  APPROX_QUANTILES(los_days, 100)[4] - APPROX_QUANTILES(los_days, 100)[1] AS iqr
FROM 
  filtered_patients;