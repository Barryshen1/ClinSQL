WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT 
      p.subject_id, 
      p.anchor_age, 
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 66 AND 76
  ),
  
  -- Identify ICU stays for patients of interest
  icu_stays AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id, 
      i.intime
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      patients_of_interest p ON i.subject_id = p.subject_id
  ),
  
  -- Identify invasively ventilated patients
  ventilated_patients AS (
    SELECT 
      DISTINCT subject_id, 
      hadm_id, 
      stay_id
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE 
      itemid = 220050  -- Ventilation mode
  ),
  
  -- Systolic blood pressure measurements in the first 6 hours
  sbp_measurements AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id, 
      ce.valuenum AS sbp
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      icu_stays i ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
    WHERE 
      ce.itemid = 220050  -- SBP
      AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 6 HOUR)
  ),
  
  -- Filter for ventilated patients
  ventilated_sbp AS (
    SELECT 
      sm.sbp
    FROM 
      sbp_measurements sm
    JOIN 
      ventilated_patients vp ON sm.subject_id = vp.subject_id AND sm.hadm_id = vp.hadm_id AND sm.stay_id = vp.stay_id
  )

SELECT 
  APPROX_QUANTILES(sbp, 100)[1] AS Q1,
  APPROX_QUANTILES(sbp, 100)[3] AS Q3
FROM 
  ventilated_sbp;

-- To get IQR, you can calculate it outside this query or within
-- For demonstration, calculating IQR within:
SELECT 
  Q1,
  Q3,
  Q3 - Q1 AS IQR
FROM (
  SELECT 
    APPROX_QUANTILES(sbp, 100)[1] AS Q1,
    APPROX_QUANTILES(sbp, 100)[3] AS Q3
  FROM 
    ventilated_sbp
);