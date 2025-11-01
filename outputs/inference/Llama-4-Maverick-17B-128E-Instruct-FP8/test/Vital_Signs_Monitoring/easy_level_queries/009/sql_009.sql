WITH aged_female_patients AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 86 AND 96
),
icu_stays AS (
  SELECT i.subject_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN aged_female_patients a ON i.subject_id = a.subject_id
),
temp_data AS (
  SELECT c.valuenum, c.charttime, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_stays i ON c.stay_id = i.stay_id
  WHERE c.itemid = 223762  -- Verify the correct itemid for temperature in °F
  AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
)
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS temperature_75th_percentile
FROM temp_data;