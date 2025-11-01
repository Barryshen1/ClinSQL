WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM icu.intime))) BETWEEN 73 AND 83
),
spo2_data AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS mean_spo2
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220277
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 24 HOUR
  GROUP BY c.stay_id
)
SELECT 
  (COUNTIF(mean_spo2 <= 92) * 100.0) / COUNT(*) AS percentile
FROM spo2_data;