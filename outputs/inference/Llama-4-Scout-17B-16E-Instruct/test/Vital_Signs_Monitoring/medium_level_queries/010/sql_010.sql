WITH 
  sbp_data AS (
    SELECT 
      ic.stay_id,
      ic.subject_id,
      ic.hadm_id,
      p.anchor_age,
      p.gender,
      AVG(cv.valuenum) AS avg_sbp
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` cv
      ON ic.stay_id = cv.stay_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ic.subject_id = p.subject_id
    WHERE 
      cv.itemid = 220050  -- SBP itemid
      AND cv.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
      AND p.gender = 'F'
      AND p.anchor_age BETWEEN 77 AND 87
    GROUP BY 
      ic.stay_id, ic.subject_id, ic.hadm_id, p.anchor_age, p.gender
  )

SELECT 
  ROUND(PERCENT_RANK() OVER (ORDER BY avg_sbp), 2) AS percentile
FROM 
  sbp_data
WHERE 
  avg_sbp = 160;