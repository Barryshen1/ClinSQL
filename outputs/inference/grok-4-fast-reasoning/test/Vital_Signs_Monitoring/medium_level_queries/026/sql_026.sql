WITH eligible_stays AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON 
    p.subject_id = i.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
rr_measurements AS (
  SELECT 
    es.stay_id,
    c.valuenum,
    es.intime
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    es.stay_id = c.stay_id
  WHERE 
    c.itemid IN (618, 220339)
    AND c.valuenum IS NOT NULL
    AND c.charttime >= es.intime
    AND c.charttime < DATETIME_ADD(es.intime, INTERVAL 48 HOUR)
),
avg_rr_per_stay AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_rr
  FROM 
    rr_measurements
  GROUP BY 
    stay_id
  HAVING 
    COUNT(valuenum) >= 1  -- Only stays with at least one measurement
)
SELECT 
  (COUNTIF(avg_rr <= 12) * 100.0 / COUNT(*)) AS percentile
FROM 
  avg_rr_per_stay;