WITH eligible_stays AS (
  SELECT 
    i.stay_id, 
    i.subject_id, 
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
),
averages AS (
  SELECT 
    es.stay_id, 
    AVG(ce.valuenum) AS avg_sbp
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = es.stay_id
  WHERE ce.itemid IN (220045, 220179)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= es.intime
    AND ce.charttime <= TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
  GROUP BY es.stay_id
  HAVING avg_sbp IS NOT NULL
)
SELECT 
  COUNT(*) AS total_stays_with_bp,
  SUM(CASE WHEN avg_sbp <= 160 THEN 1 ELSE 0 END) AS num_stays_le_160,
  ROUND((SUM(CASE WHEN avg_sbp <= 160 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 2) AS percentile
FROM averages;