WITH 
  -- First, find the first recorded SpO2 for each ICU stay
  first_spo2 AS (
    SELECT 
      ic.stay_id,
      ic.subject_id,
      MIN(cv.charttime) AS first_charttime,
      cv.valuenum AS first_spo2_value
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` cv
    ON 
      ic.stay_id = cv.stay_id
    WHERE 
      cv.itemid = 220050  -- SpO2
      AND cv.charttime >= ic.intime  -- First recorded SpO2 on or after admission
    GROUP BY 
      ic.stay_id, ic.subject_id, cv.valuenum
  ),
  
  -- Then, link the first recorded SpO2 with patient demographics
  patient_spo2 AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      fs.first_spo2_value
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      first_spo2 fs
    ON 
      p.subject_id = fs.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 37 AND 47
  )

-- Finally, calculate the IQR of the first recorded SpO2
SELECT 
  APPROX_QUANTILES(first_spo2_value, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(first_spo2_value, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(first_spo2_value, 100)[OFFSET(75)] AS Q3,
  APPROX_QUANTILES(first_spo2_value, 100)[OFFSET(75)] - 
  APPROX_QUANTILES(first_spo2_value, 100)[OFFSET(25)] AS IQR
FROM 
  patient_spo2;