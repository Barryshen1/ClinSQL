WITH spo2_means AS (
  SELECT 
    AVG(ce.valuenum) AS mean_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE ce.itemid = 220277
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 1 DAY)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
  GROUP BY icu.stay_id
  HAVING COUNT(ce.valuenum) >= 1
)
SELECT 
  COUNTIF(mean_spo2 <= 92) * 100.0 / COUNT(*) AS percentile
FROM spo2_means;