WITH cohort AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND ce.itemid = 220277  -- SpO2
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.stay_id
),
percentiles AS (
  SELECT
    PERCENTILE_DISC(avg_spo2, 0.01) OVER() AS p1,
    PERCENTILE_DISC(avg_spo2, 0.05) OVER() AS p5,
    PERCENTILE_DISC(avg_spo2, 0.10) OVER() AS p10,
    PERCENTILE_DISC(avg_spo2, 0.25) OVER() AS p25,
    PERCENTILE_DISC(avg_spo2, 0.50) OVER() AS p50,
    PERCENTILE_DISC(avg_spo2, 0.75) OVER() AS p75,
    PERCENTILE_DISC(avg_spo2, 0.90) OVER() AS p90,
    PERCENTILE_DISC(avg_spo2, 0.95) OVER() AS p95,
    PERCENTILE_DISC(avg_spo2, 0.99) OVER() AS p99
  FROM cohort
  LIMIT 1
)
SELECT 
  CASE
    WHEN 88 <= p1 THEN '<=1st'
    WHEN 88 <= p5 THEN '1st-5th'
    WHEN 88 <= p10 THEN '5th-10th'
    WHEN 88 <= p25 THEN '10th-25th'
    WHEN 88 <= p50 THEN '25th-50th'
    WHEN 88 <= p75 THEN '50th-75th'
    WHEN 88 <= p90 THEN '75th-90th'
    WHEN 88 <= p95 THEN '90th-95th'
    WHEN 88 <= p99 THEN '95th-99th'
    ELSE '>99th'
  END AS percentile_range
FROM percentiles;