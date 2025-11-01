WITH eligible_stays AS (
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    pat.gender,
    pat.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON 
    icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 87 AND 97
    AND icu.first_careunit LIKE '%ICU%'
    AND icu.los >= 1
),
spo2_measurements AS (
  SELECT 
    es.stay_id,
    es.intime,
    ce.charttime,
    ce.valuenum
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    ce.subject_id = es.subject_id
    AND ce.hadm_id = es.hadm_id
    AND ce.stay_id = es.stay_id
  WHERE 
    ce.itemid IN (220277, 220339)
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.charttime >= es.intime
    AND ce.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 24 HOUR)
),
per_stay_averages AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_spo2
  FROM 
    spo2_measurements
  GROUP BY 
    stay_id
  HAVING 
    COUNT(valuenum) > 0
),
ranked_averages AS (
  SELECT 
    avg_spo2,
    PERCENT_RANK() OVER (ORDER BY avg_spo2) AS percentile_rank
  FROM 
    per_stay_averages
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY avg_spo2) AS percentile_for_88
FROM 
  ranked_averages
WHERE 
  avg_spo2 = 88
LIMIT 1;