WITH rr_data AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND ce.itemid IN (220210, 224690)  -- Respiratory Rate
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 100
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
  GROUP BY ie.stay_id
),
categorized AS (
  SELECT
    stay_id,
    avg_rr,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
      ELSE '>=30'
    END AS rr_category
  FROM rr_data
)
SELECT
  rr_category,
  COUNT(*) AS n,
  ROUND(AVG(avg_rr), 2) AS mean,
  ROUND(APPROX_QUANTILES(avg_rr, 2)[OFFSET(1)], 2) AS median,
  ROUND(APPROX_QUANTILES(avg_rr, 4)[OFFSET(3)] - APPROX_QUANTILES(avg_rr, 4)[OFFSET(1)], 2) AS iqr
FROM categorized
GROUP BY rr_category
ORDER BY rr_category;