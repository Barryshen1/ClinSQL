WITH 
  -- Identify relevant ICU stays
  eligible_stays AS (
    SELECT 
      ic.stay_id,
      ic.subject_id,
      p.anchor_age,
      ic.intime
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ic.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 65 AND 75
  ),

  -- Extract SBP measurements within the first 24 hours
  sbp_measurements AS (
    SELECT 
      es.stay_id,
      ce.charttime,
      ce.valuenum AS sbp
    FROM 
      eligible_stays es
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON es.stay_id = ce.stay_id
    WHERE 
      ce.itemid = 220050  -- SBP itemid
      AND ce.charttime BETWEEN es.intime AND TIMESTAMP_ADD(es.intime, INTERVAL 24 HOUR)
  )

SELECT 
  CASE 
    WHEN sbp < 140 THEN '<140'
    WHEN sbp BETWEEN 140 AND 159 THEN '140–159'
    ELSE '≥160'
  END AS sbp_category,
  AVG(sbp) AS mean_sbp,
  APPROX_QUANTILES(sbp, 1000)[500] AS median_sbp,
  APPROX_QUANTILES(sbp, 1000)[250] AS q1_sbp,
  APPROX_QUANTILES(sbp, 1000)[750] AS q3_sbp
FROM 
  sbp_measurements
GROUP BY 
  CASE 
    WHEN sbp < 140 THEN '<140'
    WHEN sbp BETWEEN 140 AND 159 THEN '140–159'
    ELSE '≥160'
  END;