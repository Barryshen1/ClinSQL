WITH 
  -- Identify AKI admissions
  aki_admissions AS (
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
      p.gender = 'M'
      AND p.anchor_age BETWEEN 37 AND 47
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code IN ('584', 'N17')  -- ICD-9 and ICD-10 codes for AKI
          AND seq_num = 1  -- Primary diagnosis
      )
  ),

  -- Calculate hospital LOS in days
  los_data AS (
    SELECT 
      hadm_id,
      admittime,
      dischtime,
      (TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS los_days
    FROM 
      aki_admissions
  )

SELECT 
  APPROX_QUANTILES(los_days, 1000)[75] AS percentile_75_los
FROM 
  los_data;