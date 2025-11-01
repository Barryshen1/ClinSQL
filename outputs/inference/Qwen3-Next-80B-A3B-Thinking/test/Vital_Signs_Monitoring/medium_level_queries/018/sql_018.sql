WITH means AS (
  SELECT 
    i.stay_id,
    AVG(c.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
    AND c.itemid = 220050
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL 48 HOUR
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND c.valuenum IS NOT NULL
  GROUP BY i.stay_id
)
SELECT 
  (COUNT(CASE WHEN mean_sbp <= 140 THEN 1 END) * 100.0) / COUNT(*) AS percentile
FROM means;