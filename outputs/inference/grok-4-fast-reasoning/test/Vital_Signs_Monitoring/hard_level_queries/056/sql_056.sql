WITH eligible_stays AS (
  SELECT 
    i.stay_id, 
    i.subject_id, 
    i.intime, 
    i.los, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),
unstable_events AS (
  -- Fever: Temperature C > 38.5
  SELECT 
    es.stay_id, 
    FLOOR(TIMESTAMP_DIFF(c.charttime, es.intime, MINUTE) / 60) AS hour_bin, 
    1 AS fever_flag, 
    0 AS spo2_flag, 
    0 AS rr_flag
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON c.stay_id = es.stay_id
  WHERE c.itemid = 676 
    AND c.valuenum > 38.5
    AND c.charttime >= es.intime
    AND c.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
  
  UNION ALL
  
  -- Fever: Temperature F > 101.3 (equiv to 38.5 C)
  SELECT 
    es.stay_id, 
    FLOOR(TIMESTAMP_DIFF(c.charttime, es.intime, MINUTE) / 60) AS hour_bin, 
    1 AS fever_flag, 
    0 AS spo2_flag, 
    0 AS rr_flag
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON c.stay_id = es.stay_id
  WHERE c.itemid = 678 
    AND c.valuenum > 101.3
    AND c.charttime >= es.intime
    AND c.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
  
  UNION ALL
  
  -- Hypoxemia: SpO2 < 90
  SELECT 
    es.stay_id, 
    FLOOR(TIMESTAMP_DIFF(c.charttime, es.intime, MINUTE) / 60) AS hour_bin, 
    0 AS fever_flag, 
    1 AS spo2_flag, 
    0 AS rr_flag
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON c.stay_id = es.stay_id
  WHERE c.itemid = 220277 
    AND c.valuenum < 90
    AND c.charttime >= es.intime
    AND c.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
  
  UNION ALL
  
  -- Tachypnea: RR > 20
  SELECT 
    es.stay_id, 
    FLOOR(TIMESTAMP_DIFF(c.charttime, es.intime, MINUTE) / 60) AS hour_bin, 
    0 AS fever_flag, 
    0 AS spo2_flag, 
    1 AS rr_flag
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON c.stay_id = es.stay_id
  WHERE c.itemid IN (618, 220210)
    AND c.valuenum > 20
    AND c.charttime >= es.intime
    AND c.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
),
component_hours AS (
  SELECT 
    stay_id,
    COUNT(DISTINCT CASE WHEN fever_flag = 1 THEN hour_bin END) AS fever_h,
    COUNT(DISTINCT CASE WHEN spo2_flag = 1 THEN hour_bin END) AS spo2_h,
    COUNT(DISTINCT CASE WHEN rr_flag = 1 THEN hour_bin END) AS rr_h,
    COUNT(DISTINCT hour_bin) AS instability_h
  FROM unstable_events
  GROUP BY stay_id
),
all_stays AS (
  SELECT 
    es.stay_id,
    es.los,
    es.hospital_expire_flag,
    COALESCE(ch.instability_h, 0) AS instability_h,
    COALESCE(ch.fever_h, 0) AS fever_h,
    COALESCE(ch.spo2_h, 0) AS spo2_h,
    COALESCE(ch.rr_h, 0) AS rr_h
  FROM eligible_stays es
  LEFT JOIN component_hours ch 
    ON ch.stay_id = es.stay_id
),
threshold AS (
  SELECT APPROX_QUANTILES(instability_h, 10)[OFFSET(9)] AS p90 
  FROM all_stays
),
top_decile AS (
  SELECT *
  FROM all_stays
  WHERE instability_h >= (SELECT p90 FROM threshold)
)
SELECT 
  (SELECT p90 FROM threshold) AS percentile_90_instability,
  COUNT(*) AS n,
  AVG(los) AS mean_icu_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(fever_h) AS mean_fever_hours,
  AVG(spo2_h) AS mean_hypoxemia_hours,
  AVG(rr_h) AS mean_tachypnea_hours
FROM top_decile;