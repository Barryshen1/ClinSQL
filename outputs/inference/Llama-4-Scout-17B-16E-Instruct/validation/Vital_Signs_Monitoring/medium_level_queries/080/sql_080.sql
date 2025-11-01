WITH 
  -- Filter patients, get relevant information, and extract MAP values for each ICU stay within the first 48 hours
  patient_map_values AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      ic.stay_id,
      ic.intime,
      cv.charttime,
      cv.valuenum AS map_value
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON p.subject_id = ic.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` cv 
        ON p.subject_id = cv.subject_id AND ic.stay_id = cv.stay_id
    WHERE 
      p.gender = 'F' AND p.anchor_age BETWEEN 56 AND 66
      AND cv.itemid = 220050  -- MAP itemid
      AND cv.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
  ),
  
  -- Calculate mean MAP for each stay and categorize
  categorized_map AS (
    SELECT 
      stay_id,
      AVG(map_value) AS mean_map,
      CASE 
        WHEN AVG(map_value) < 65 THEN '<65'
        WHEN AVG(map_value) BETWEEN 65 AND 74 THEN '65–74'
        WHEN AVG(map_value) BETWEEN 75 AND 84 THEN '75–84'
        ELSE '≥85'
      END AS map_category
    FROM 
      patient_map_values
    GROUP BY 
      stay_id
  )

-- Calculate statistics for each category
SELECT 
  map_category,
  COUNT(*) AS count,
  AVG(mean_map) AS mean,
  APPROX_QUANTILES(mean_map, 0.5)[OFFSET(0)] AS median,
  APPROX_QUANTILES(mean_map, 0.25)[OFFSET(0)] AS q1,
  APPROX_QUANTILES(mean_map, 0.75)[OFFSET(0)] AS q3
FROM 
  categorized_map
GROUP BY 
  map_category;