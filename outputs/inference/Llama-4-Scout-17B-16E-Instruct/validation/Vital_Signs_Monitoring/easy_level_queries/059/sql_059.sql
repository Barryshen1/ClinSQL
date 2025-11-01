WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age BETWEEN 77 AND 87
    AND gender = 'M'
  ),
  
  -- Find first recorded SpO2 for each admission
  first_spo2 AS (
    SELECT 
      a.hadm_id,
      c.value AS first_spo2_value
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` c 
        ON a.hadm_id = c.hadm_id
    JOIN 
      target_patients tp ON a.subject_id = tp.subject_id
    WHERE 
      c.itemid = 220050  -- SpO2 itemid in chartevents
      AND c.valueuom = '%'  -- Ensure value is in percentage
      AND REGEXP_CONTAINS(c.value, r'^\d+(\.\d+)?$')  -- Ensure value is numeric
  )

-- Calculate standard deviation of first recorded SpO2
SELECT 
  STDDEV(SAFE_CAST(first_spo2_value AS FLOAT64)) AS std_dev_first_spo2
FROM 
  first_spo2;