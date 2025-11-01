WITH target_patients AS (
  SELECT 
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),

vital_events AS (
  SELECT 
    ce.stay_id,
    DATETIME_TRUNC(ce.charttime, HOUR) AS hour_bin,
    CASE 
      WHEN di.label = 'Temperature' AND ce.valuenum > 38.5 THEN 1 
      ELSE 0 
    END AS has_fever,
    CASE 
      WHEN di.label = 'SpO2' AND ce.valuenum < 90 THEN 1 
      ELSE 0 
    END AS has_hypoxemia,
    CASE 
      WHEN di.label = 'Respiratory Rate' AND ce.valuenum > 20 THEN 1 
      ELSE 0 
    END AS has_tachypnea
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN target_patients tp
    ON ce.stay_id = tp.stay_id
  WHERE ce.charttime >= tp.intime
    AND ce.charttime < DATETIME_ADD(tp.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND di.label IN ('Temperature', 'SpO2', 'Respiratory Rate')
),

instability_hours AS (
  SELECT 
    stay_id,
    COUNT(DISTINCT CASE WHEN has_fever = 1 OR has_hypoxemia = 1 OR has_tachypnea = 1 THEN hour_bin END) AS total_instability_hours,
    COUNT(DISTINCT CASE WHEN has_fever = 1 THEN hour_bin END) AS fever_hours,
    COUNT(DISTINCT CASE WHEN has_hypoxemia = 1 THEN hour_bin END) AS hypoxemia_hours,
    COUNT(DISTINCT CASE WHEN has_tachypnea = 1 THEN hour_bin END) AS tachypnea_hours
  FROM vital_events
  GROUP BY stay_id
),

percentile_90 AS (
  SELECT PERCENTILE_CONT(total_instability_hours, 0.9) OVER () AS p90_instability
  FROM instability_hours
  LIMIT 1
),

top_decile AS (
  SELECT 
    ih.*,
    tp.los,
    tp.hospital_expire_flag
  FROM instability_hours ih
  INNER JOIN target_patients tp ON ih.stay_id = tp.stay_id
  CROSS JOIN percentile_90 p90
  WHERE ih.total_instability_hours >= p90.p90_instability
)

SELECT 
  COUNT(*) AS n,
  AVG(los) AS mean_icu_los,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  AVG(fever_hours) AS mean_hours_fever,
  AVG(hypoxemia_hours) AS mean_hours_hypoxemia,
  AVG(tachypnea_hours) AS mean_hours_tachypnea
FROM top_decile;