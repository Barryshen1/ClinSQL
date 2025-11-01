WITH sbp_data AS (
  SELECT 
    ce.valuenum AS sbp_value,
    CASE 
      WHEN ce.valuenum < 140 THEN '<140'
      WHEN ce.valuenum BETWEEN 140 AND 159 THEN '140-159'
      WHEN ce.valuenum >= 160 THEN '>=160'
    END AS sbp_category
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON ie.stay_id = ce.stay_id
      AND ce.itemid IN (220179, 225309)  -- SBP itemids
      AND ce.valuenum IS NOT NULL
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
)
SELECT 
  sbp_category,
  COUNT(*) AS measurement_count,
  AVG(sbp_value) AS mean_sbp,
  APPROX_QUANTILES(sbp_value, 100)[OFFSET(50)] AS median_sbp,
  APPROX_QUANTILES(sbp_value, 100)[OFFSET(25)] AS q1_sbp,
  APPROX_QUANTILES(sbp_value, 100)[OFFSET(75)] AS q3_sbp
FROM sbp_data
WHERE sbp_category IS NOT NULL
GROUP BY sbp_category
ORDER BY sbp_category;