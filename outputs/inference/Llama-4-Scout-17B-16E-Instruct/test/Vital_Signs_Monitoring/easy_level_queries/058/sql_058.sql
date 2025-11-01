WITH 
  -- Identify temperature itemids
  temp_itemids AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%temperature%'
  ),
  
  -- Extract temperature data for men aged 74-84
  patient_temps AS (
    SELECT 
      ic.stay_id,
      ic.subject_id,
      p.anchor_age,
      ce.valuenum AS temp_value
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ic.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ic.stay_id = ce.stay_id
    JOIN 
      temp_itemids ti ON ce.itemid = ti.itemid
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 74 AND 84
      AND ce.valuenum IS NOT NULL
  )

-- Calculate median of minimum temperature per stay
SELECT 
  APPROX_QUANTILES(min_temp, 100)[OFFSET(50)] AS median_min_temp
FROM (
  SELECT 
    stay_id,
    MIN(temp_value) AS min_temp
  FROM 
    patient_temps
  GROUP BY 
    stay_id
);