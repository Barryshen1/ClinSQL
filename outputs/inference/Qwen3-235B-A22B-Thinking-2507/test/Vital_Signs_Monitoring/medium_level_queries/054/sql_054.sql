WITH icu_stays_filtered AS (
  SELECT 
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE 
    patients.gender = 'F'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 87 AND 97
),
sbp_measurements AS (
  SELECT 
    icu_stays_filtered.stay_id,
    chartevents.valuenum AS sbp
  FROM icu_stays_filtered
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
    ON icu_stays_filtered.stay_id = chartevents.stay_id
  WHERE 
    chartevents.valuenum IS NOT NULL
    AND chartevents.charttime >= icu_stays_filtered.intime
    AND chartevents.charttime < TIMESTAMP_ADD(icu_stays_filtered.intime, INTERVAL 24 HOUR)
    AND chartevents.itemid IN (220050, 220179)  -- Systolic BP itemids
),
stay_avg_sbp AS (
  SELECT 
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM sbp_measurements
  GROUP BY stay_id
)
SELECT 
  (COUNTIF(avg_sbp <= 150) * 100.0) / COUNT(*) AS percentile
FROM stay_avg_sbp;