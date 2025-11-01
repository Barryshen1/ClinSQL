WITH 
  -- Filter patients and calculate average temperature over first 48h
  patient_temps AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      icu.stay_id,
      AVG(CASE 
        WHEN c.itemid = 220050 AND c.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR) 
        THEN c.valuenum 
        END) AS avg_temp
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` c ON icu.stay_id = c.stay_id
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 71 AND 81
    GROUP BY 
      p.subject_id, p.anchor_age, icu.stay_id
  ),

  -- Categorize temperatures
  temp_categories AS (
    SELECT 
      subject_id,
      stay_id,
      anchor_age,
      avg_temp,
      CASE 
        WHEN avg_temp < 36.0 THEN '<36.0'
        WHEN avg_temp BETWEEN 36.0 AND 37.9 THEN '36.0-37.9'
        ELSE '>=38.0'
      END AS temp_category
    FROM 
      patient_temps
  ),

  -- Calculate mortality rate
  mortality_rate AS (
    SELECT 
      tc.temp_category,
      COUNT(DISTINCT CASE WHEN a.hospital_expire_flag = 1 THEN tc.subject_id END) AS deaths,
      COUNT(DISTINCT tc.subject_id) AS total_patients
    FROM 
      temp_categories tc
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON tc.subject_id = a.subject_id
    GROUP BY 
      tc.temp_category
  )

-- Calculate mean, median, IQR for each category
SELECT 
  tc.temp_category,
  AVG(tc.avg_temp) AS mean_temp,
  PERCENTILE_CONT(0.5)(tc.avg_temp) AS median_temp,
  PERCENTILE_CONT(0.25)(tc.avg_temp) AS q1,
  PERCENTILE_CONT(0.75)(tc.avg_temp) AS q3,
  mr.deaths * 1.0 / mr.total_patients AS mortality_rate
FROM 
  temp_categories tc
JOIN 
  mortality_rate mr ON tc.temp_category = mr.temp_category
GROUP BY 
  tc.temp_category, mr.deaths, mr.total_patients;