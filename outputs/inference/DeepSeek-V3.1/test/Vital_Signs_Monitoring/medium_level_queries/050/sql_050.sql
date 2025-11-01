WITH hr_avg_per_stay AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND ce.itemid IN (220045, 211)  -- Heart Rate itemids
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= ie.intime
    AND ce.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.stay_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(avg_hr, 100) AS pct
  FROM hr_avg_per_stay
)
SELECT 
  pct[OFFSET(0)] AS min,
  pct[OFFSET(10)] AS p10,
  pct[OFFSET(25)] AS p25,
  pct[OFFSET(50)] AS p50,
  pct[OFFSET(75)] AS p75,
  pct[OFFSET(90)] AS p90,
  pct[OFFSET(100)] AS max,
  -- Find the percentile where 110 falls
  (
    SELECT MAX(offset) 
    FROM UNNEST(pct) AS value WITH OFFSET offset 
    WHERE value <= 110
  ) AS percentile_rank
FROM percentiles;