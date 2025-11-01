WITH 
relevant_icustays AS (
  SELECT i.stay_id, i.intime, i.intime + INTERVAL 24 HOUR AS intime_24h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 65 AND 75
),
systolic_bps AS (
  SELECT c.valuenum AS systolic_bp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN relevant_icustays r 
    ON c.stay_id = r.stay_id
  WHERE c.itemid = 220050  
    AND c.charttime >= r.intime AND c.charttime < r.intime_24h
),
categorized_bps AS (
  SELECT 
    CASE 
      WHEN systolic_bp < 140 THEN '<140'
      WHEN systolic_bp BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS bp_category,
    systolic_bp
  FROM systolic_bps
)
SELECT 
  bp_category,
  COUNT(*) AS count,
  AVG(systolic_bp) AS mean,
  APPROX_QUANTILES(systolic_bp, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(systolic_bp, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(systolic_bp, 100)[OFFSET(75)] AS q3
FROM categorized_bps
GROUP BY bp_category
ORDER BY bp_category;