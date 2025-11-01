WITH eligible_stays AS (
  SELECT 
    s.stay_id, 
    s.intime,
    p.gender, 
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 54 AND 64
),
rr_measurements AS (
  SELECT 
    ce.stay_id, 
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN eligible_stays es 
    ON ce.stay_id = es.stay_id
  WHERE ce.itemid = 618
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0
    AND ce.charttime >= es.intime
    AND ce.charttime < DATE_ADD(es.intime, INTERVAL 48 HOUR)
),
avg_rr_per_stay AS (
  SELECT 
    stay_id, 
    AVG(valuenum) AS avg_rr
  FROM rr_measurements
  GROUP BY stay_id
  HAVING COUNT(valuenum) > 0
)
SELECT 
  category,
  COUNT(*) AS n,
  ROUND(AVG(avg_rr), 2) AS mean,
  ROUND(APPROX_QUANTILES(avg_rr, 2)[OFFSET(1)], 2) AS median,
  ROUND((APPROX_QUANTILES(avg_rr, 4)[OFFSET(3)] - APPROX_QUANTILES(avg_rr, 4)[OFFSET(1)]), 2) AS iqr
FROM (
  SELECT 
    avg_rr,
    CASE 
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12-20'
      WHEN avg_rr >= 21 AND avg_rr <= 29 THEN '21-29'
      ELSE '>=30'
    END AS category
  FROM avg_rr_per_stay
)
GROUP BY category
ORDER BY 
  CASE category 
    WHEN '<12' THEN 1 
    WHEN '12-20' THEN 2 
    WHEN '21-29' THEN 3 
    ELSE 4 
  END;