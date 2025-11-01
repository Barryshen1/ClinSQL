WITH icu_stays_filtered AS (
  SELECT 
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 86 AND 96
),
temp_measurements AS (
  SELECT 
    (ce.valuenum * 9/5) + 32 AS temp_fahrenheit
  FROM icu_stays_filtered icu
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  WHERE ce.itemid = 223761
    AND ce.charttime >= icu.intime
    AND ce.charttime <= icu.intime + INTERVAL '24' HOUR
    AND ce.valuenum IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(temp_fahrenheit, 0.75) OVER () AS p75_temp_f
FROM temp_measurements
LIMIT 1;