WITH 
  -- Filter patients and admissions of interest
  patients_of_interest AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      a.discharge_location,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.anchor_age BETWEEN 88 AND 98
      AND a.admission_type = 'Elective'
  ),

  -- Calculate discharge outcomes and LOS
  discharge_outcomes AS (
    SELECT 
      hadm_id,
      admittime,
      dischtime,
      CASE 
        WHEN discharge_location = 'Home' THEN 'Home'
        WHEN discharge_location IN ('SNF', 'Rehab', 'LTACH') THEN 'SNF/Rehab/LTACH'
        WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
        ELSE 'Other'
      END AS discharge_outcome,
      DATE_DIFF(dischtime, admittime, DAY) AS LOS
    FROM 
      patients_of_interest
  ),

  -- Filter discharge outcomes of interest
  filtered_outcomes AS (
    SELECT 
      discharge_outcome,
      LOS
    FROM 
      discharge_outcomes
    WHERE 
      discharge_outcome IN ('Home', 'SNF/Rehab/LTACH', 'In-hospital death')
  )

-- Calculate statistics
SELECT 
  discharge_outcome,
  AVG(LOS) AS mean_LOS,
  PERCENTILE_CONT(0.5, LOS) AS median_LOS,
  PERCENTILE_CONT(0.75, LOS) AS p75_LOS,
  PERCENTILE_CONT(0.9, LOS) AS p90_LOS,
  SUM(CASE WHEN LOS <= 7 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_LOS_leq_7_days
FROM 
  filtered_outcomes
GROUP BY 
  discharge_outcome;