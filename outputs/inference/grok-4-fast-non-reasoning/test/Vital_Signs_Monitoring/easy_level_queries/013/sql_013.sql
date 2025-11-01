WITH eligible_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND i.first_careunit NOT LIKE '%N%'
),
heart_rates AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS heart_rate
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    eligible_stays es
  ON 
    ce.stay_id = es.stay_id
  WHERE 
    ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= es.intime
    AND ce.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 24 HOUR)
)
SELECT 
  MIN(heart_rate) AS min_heart_rate
FROM 
  heart_rates;