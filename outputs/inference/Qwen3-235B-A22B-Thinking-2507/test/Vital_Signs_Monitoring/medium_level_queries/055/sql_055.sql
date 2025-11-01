WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 87 AND 97
),
spo2_measurements AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS spo2
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220277  -- Standard SpO2 itemid
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),
stay_averages AS (
  SELECT 
    stay_id,
    AVG(spo2) AS avg_spo2
  FROM spo2_measurements
  GROUP BY stay_id
)
SELECT 
  100.0 * COUNTIF(avg_spo2 <= 88) / COUNT(*) AS percentile
FROM stay_averages;