WITH 
  patients_of_interest AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.admission_location,
      a.discharge_location,
      a.hospital_expire_flag,
      i.stay_id,
      i.intime,
      i.outtime,
      i.los,
      CASE 
        WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
        WHEN a.discharge_location = 'Home' THEN 'Home'
        ELSE 'Facility'
      END AS discharge_status
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON a.hadm_id = i.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 52 AND 62
      AND a.admission_location != 'Home'
  )

SELECT 
  discharge_status,
  COUNT(*) AS total_patients,
  AVG(los) AS mean_los,
  STDDEV(los) AS sd_los,
  APPROX_QUANTILES(los, 100)[5] AS percentile_50_los,  -- 50th percentile (median)
  COUNT(CASE WHEN los <= 5 THEN hadm_id END) * 1.0 / COUNT(hadm_id) AS proportion_5_day_los
FROM 
  patients_of_interest
GROUP BY 
  discharge_status;