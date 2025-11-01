WITH qualifying_stays AS (
  SELECT 
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),
first24_avgs AS (
  SELECT 
    qs.stay_id,
    AVG(ce.valuenum) AS avg_sys_bp
  FROM qualifying_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = qs.stay_id
    AND ce.itemid IN (220050, 220179)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= qs.intime
    AND ce.charttime < TIMESTAMP_ADD(qs.intime, INTERVAL 24 HOUR)
  GROUP BY qs.stay_id
  HAVING COUNT(ce.valuenum) > 0  -- Ensure at least one measurement
)
SELECT 
  COUNT(*) AS num_stays_with_bp,
  COUNTIF(avg_sys_bp <= 150) AS num_stays_le_150,
  ROUND(COUNTIF(avg_sys_bp <= 150) * 100.0 / COUNT(*), 2) AS percentile
FROM first24_avgs;