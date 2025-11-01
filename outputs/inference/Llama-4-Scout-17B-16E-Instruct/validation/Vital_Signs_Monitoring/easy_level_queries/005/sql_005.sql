WITH 
  -- Define systolic blood pressure itemid
  sbp_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%Systolic Blood Pressure%'
  ),
  
  -- Select relevant patient and chart data
  patient_data AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      cv.value AS sbp_value
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` cv
    JOIN 
      `physionet-data.mimiciv_3_1_icu.d_items` di 
      ON cv.itemid = di.itemid
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON cv.subject_id = icu.subject_id AND cv.hadm_id = icu.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` adm 
      ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON adm.subject_id = p.subject_id
    WHERE 
      di.itemid = (SELECT itemid FROM sbp_itemid)
      AND p.gender = 'F'
      AND p.anchor_age BETWEEN 59 AND 69
  )

-- Calculate 75th percentile of systolic BP
SELECT 
  APPROX_QUANTILES(CAST(sbp_value AS FLOAT64), 100)[OFFSET(75)] AS percentile_75
FROM 
  patient_data;