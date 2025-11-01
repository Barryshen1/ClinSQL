WITH 
  -- Identify SBP itemid
  sbp_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%Systolic Blood Pressure%'
  ),
  
  -- Filter patients and extract SBP values within the first 24 hours
  patient_sbp AS (
    SELECT 
      ic.stay_id,
      ic.subject_id,
      ce.charttime,
      ce.valuenum AS sbp_value
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ic.stay_id = ce.stay_id
    JOIN 
      sbp_itemid si ON ce.itemid = si.itemid
    WHERE 
      ic.intime <= ce.charttime 
      AND ce.charttime <= ic.intime + INTERVAL 1 DAY
      AND ic.subject_id IN (
        SELECT subject_id 
        FROM `physionet-data.mimiciv_3_1_hosp.patients` 
        WHERE gender = 'F' 
          AND anchor_age BETWEEN 38 AND 48
      )
  ),
  
  -- Calculate average SBP per stay
  avg_sbp AS (
    SELECT 
      stay_id,
      AVG(sbp_value) AS avg_sbp_value
    FROM 
      patient_sbp
    GROUP BY 
      stay_id
  )

-- Estimate percentile of 120 mmHg
SELECT 
  CUME_DIST() OVER (ORDER BY avg_sbp_value) AS cume_dist
FROM 
  avg_sbp
WHERE 
  avg_sbp_value <= 120;