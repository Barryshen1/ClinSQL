WITH 
  -- Filter and prepare patient data
  patients_data AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      p.anchor_age,
      p.gender,
      CASE 
        WHEN t.eventtype = 'transfer in' THEN TRUE
        ELSE FALSE
      END AS transferred_in
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.transfers` t 
      ON a.hadm_id = t.hadm_id AND t.eventtype = 'transfer in'
  ),
  
  -- Determine discharge outcomes and LOS
  outcomes_data AS (
    SELECT 
      pd.hadm_id,
      pd.subject_id,
      pd.anchor_age,
      pd.gender,
      pd.transferred_in,
      CASE 
        WHEN a.discharge_location = 'home' THEN 'home'
        WHEN a.discharge_location = 'facility' THEN 'facility'
        WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
        ELSE 'other'
      END AS discharge_outcome,
      COALESCE( 
        (SELECT los FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE hadm_id = pd.hadm_id),
        DATE_DIFF(a.dischtime, a.admittime, DAY)
      ) AS los
    FROM 
      patients_data pd
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON pd.hadm_id = a.hadm_id
  )

-- Filter males aged 43-53 transferred inpatients and calculate statistics
SELECT 
  discharge_outcome,
  APPROX_QUANTILES(los, 0.5)[OFFSET(0)] AS median_los,
  APPROX_QUANTILES(los, 0.25)[OFFSET(0)] AS los_q1,
  APPROX_QUANTILES(los, 0.75)[OFFSET(0)] AS los_q3,
  SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(los) * 100 AS pct_los_10_days
FROM 
  outcomes_data
WHERE 
  gender = 'M' AND anchor_age BETWEEN 43 AND 53 AND transferred_in
GROUP BY 
  discharge_outcome;