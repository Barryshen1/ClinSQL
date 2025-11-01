WITH 
  -- Identify itemid for Respiratory Rate
  rr_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label = 'Respiratory Rate'
  ),

  -- Select relevant patient and ICU stay information
  patients_info AS (
    SELECT 
      p.subject_id, 
      p.anchor_age, 
      p.gender, 
      ic.stay_id, 
      ic.hadm_id, 
      ic.intime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON p.subject_id = ic.subject_id
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 54 AND 64
  ),

  -- Extract RR measurements within the first 48 hours of ICU stay
  rr_measurements AS (
    SELECT 
      pi.stay_id, 
      cv.charttime, 
      cv.valuenum AS rr_value
    FROM 
      patients_info pi
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` cv 
    ON pi.subject_id = cv.subject_id AND pi.hadm_id = cv.hadm_id
    CROSS JOIN 
      rr_itemid ri
    WHERE 
      cv.itemid = ri.itemid AND 
      cv.charttime BETWEEN pi.intime AND TIMESTAMP_ADD(pi.intime, INTERVAL 48 HOUR)
  ),

  -- Calculate average RR per stay and categorize
  categorized_rr AS (
    SELECT 
      stay_id,
      avg_rr,
      CASE 
        WHEN avg_rr < 12 THEN '<12'
        WHEN avg_rr BETWEEN 12 AND 20 THEN '12–20'
        WHEN avg_rr BETWEEN 21 AND 29 THEN '21–29'
        ELSE '≥30'
      END AS rr_category
    FROM 
      (
        SELECT 
          stay_id,
          AVG(rr_value) AS avg_rr
        FROM 
          rr_measurements
        GROUP BY 
          stay_id
      ) AS avg_rrs
  )

-- Compute statistics
SELECT 
  rr_category,
  COUNT(*) AS n,
  AVG(avg_rr) AS mean,
  APPROX_QUANTILES(avg_rr, 0.5)[OFFSET(1)] AS median,
  APPROX_QUANTILES(avg_rr, 0.25)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(avg_rr, 0.75)[OFFSET(1)] AS q3,
  APPROX_QUANTILES(avg_rr, 0.75)[OFFSET(1)] - APPROX_QUANTILES(avg_rr, 0.25)[OFFSET(1)] AS iqr
FROM 
  categorized_rr
GROUP BY 
  rr_category;