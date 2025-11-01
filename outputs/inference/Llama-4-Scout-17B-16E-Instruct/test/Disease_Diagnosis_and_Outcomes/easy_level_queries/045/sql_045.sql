WITH 
  -- Filter patients and calculate hospital LOS in days
  patient_los AS (
    SELECT 
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      COALESCE(a.dischtime, a.deathtime) AS discharge_time,
      DATE_DIFF(COALESCE(a.dischtime, a.deathtime), a.admittime, 'day') AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 77 AND 87
      AND a.hadm_id IN (
        SELECT 
          hadm_id 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
        WHERE 
          icd_code IN (
            -- Heart Failure
            '428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9',
            'I50.0', 'I50.1', 'I50.2', 'I50.8', 'I50.9',
            -- COPD
            '496.0', '496.1', '496.2', '496.3', '496.4', '496.5', '496.6', '496.7', '496.8', '496.9',
            'J44.0', 'J44.1', 'J44.8', 'J44.9'
          )
      )
  )
-- Calculate SD of hospital LOS
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM 
  patient_los;