WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age >= 67
    AND anchor_age <= 77
),
eligible_stays AS (
  SELECT es.stay_id, es.subject_id, es.hadm_id, es.intime
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` es
    ON ep.subject_id = es.subject_id
),
hr_measurements AS (
  SELECT es.stay_id, ce.valuenum
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON es.subject_id = ce.subject_id
    AND es.hadm_id = ce.hadm_id
    AND es.stay_id = ce.stay_id
  WHERE ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= es.intime
    AND ce.charttime <= TIMESTAMP_ADD(es.intime, INTERVAL 24 HOUR)
),
stay_averages AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_hr
  FROM hr_measurements
  GROUP BY stay_id
  HAVING avg_hr IS NOT NULL  -- Ensures at least one measurement
),
percentile_calc AS (
  SELECT 
    COUNT(*) AS total_stays,
    SUM(CASE WHEN avg_hr <= 110 THEN 1 ELSE 0 END) AS stays_le_110
  FROM stay_averages
)
SELECT 
  (stays_le_110 * 100.0 / total_stays) AS percentile
FROM percentile_calc;