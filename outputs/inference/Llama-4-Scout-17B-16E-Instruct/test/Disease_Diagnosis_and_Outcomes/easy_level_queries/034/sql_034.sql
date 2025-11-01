WITH 
  -- Identify sepsis/septic shock admissions
  sepsis_admissions AS (
    SELECT 
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
      p.gender = 'F'
      AND p.anchor_age BETWEEN 40 AND 50
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code IN ('038', '785.2', 'A40', 'A41')  # Example ICD codes for sepsis/septic shock
          AND seq_num = 1  # Primary diagnosis
      )
  ),
  -- Calculate LOS for these admissions
  los_data AS (
    SELECT 
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
    FROM 
      sepsis_admissions
  )
-- Calculate IQR of LOS
SELECT 
  APPROX_QUANTILES(los_days, 4)[1] AS q1_los,
  APPROX_QUANTILES(los_days, 4)[2] AS median_los,
  APPROX_QUANTILES(los_days, 4)[3] AS q3_los,
  APPROX_QUANTILES(los_days, 4)[3] - APPROX_QUANTILES(los_days, 4)[1] AS iqr_los
FROM 
  los_data;