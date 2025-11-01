WITH icu_stays_filtered AS (
  SELECT 
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 67 AND 77
),
temperature_averages AS (
  SELECT 
    f.stay_id,
    AVG(c.valuenum) AS avg_temp
  FROM icu_stays_filtered f
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.stay_id = c.stay_id
  WHERE c.itemid = 223762
    AND c.charttime >= f.intime
    AND c.charttime < TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
  GROUP BY f.stay_id
)
SELECT 
  (COUNTIF(avg_temp <= 36.0) * 100.0) / COUNT(*) AS percentile
FROM temperature_averages;