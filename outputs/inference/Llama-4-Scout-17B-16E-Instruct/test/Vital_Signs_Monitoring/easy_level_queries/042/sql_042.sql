WITH 
  -- Filter and join relevant data
  patient_data AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      ic.stay_id,
      ic.intime,
      ic.outtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON p.subject_id = ic.subject_id
    WHERE 
      p.gender = 'F' AND 
      p.anchor_age BETWEEN 63 AND 73
  ),
  
  -- Extract respiratory rate data
  respiratory_rates AS (
    SELECT 
      pd.subject_id,
      pd.stay_id,
      MAX(CASE 
        WHEN ce.itemid = 220050 or ce.itemid = 220179 THEN ce.valuenum 
        ELSE NULL 
      END) AS max_respiratory_rate
    FROM 
      patient_data pd
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON pd.stay_id = ce.stay_id AND pd.subject_id = ce.subject_id
    GROUP BY 
      pd.subject_id, pd.stay_id
  )

-- Calculate standard deviation of maximum respiratory rates
SELECT 
  STDDEV(max_respiratory_rate) AS std_dev_max_rr
FROM 
  respiratory_rates
WHERE 
  max_respiratory_rate IS NOT NULL;