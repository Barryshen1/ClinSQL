WITH eligible_stays AS (
  SELECT 
    s.stay_id,
    s.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year)) BETWEEN 68 AND 78
),
respiratory_rates AS (
  SELECT 
    e.stay_id,
    c.valuenum AS resp_rate
  FROM eligible_stays e
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON e.stay_id = c.stay_id
  WHERE c.itemid = 220210  -- Standard respiratory rate item ID
    AND c.charttime >= e.intime
    AND c.charttime <= DATETIME_ADD(e.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0  -- Valid respiratory rates must be positive
),
stay_averages AS (
  SELECT 
    stay_id,
    AVG(resp_rate) AS avg_rr
  FROM respiratory_rates
  GROUP BY stay_id
)
SELECT 
  (COUNTIF(avg_rr <= 12) * 100.0) / COUNT(*) AS percentile
FROM stay_averages;