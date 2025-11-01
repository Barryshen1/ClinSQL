WITH qualifying_stays AS (
  SELECT 
    s.stay_id, 
    s.subject_id, 
    s.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON s.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age >= 87 
    AND p.anchor_age <= 97
),
stay_avgs AS (
  SELECT 
    qs.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM 
    qualifying_stays qs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ce.stay_id = qs.stay_id
  WHERE 
    ce.itemid = 220277
    AND ce.charttime >= qs.intime
    AND ce.charttime < TIMESTAMP_ADD(qs.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum >= 0 
    AND ce.valuenum <= 100
  GROUP BY 
    qs.stay_id
  HAVING 
    avg_spo2 IS NOT NULL
)
SELECT 
  (COUNTIF(avg_spo2 <= 88) / COUNT(*) * 100.0) AS percentile
FROM 
  stay_avgs;