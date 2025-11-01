WITH temperature_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND LOWER(category) LIKE '%vital signs%'
),
patient_icu_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_icu_admit,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 82 AND 92
),
temperature_measurements AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS temperature
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN temperature_items ti ON ce.itemid = ti.itemid
  JOIN patient_icu_ages pia ON ce.stay_id = pia.stay_id
  WHERE ce.charttime >= pia.intime
    AND ce.charttime < DATETIME_ADD(pia.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),
avg_temp_per_stay AS (
  SELECT
    stay_id,
    AVG(temperature) AS avg_temperature
  FROM temperature_measurements
  GROUP BY stay_id
),
percentile_ranks AS (
  SELECT
    avg_temperature,
    PERCENT_RANK() OVER (ORDER BY avg_temperature) AS percentile_rank
  FROM avg_temp_per_stay
)
SELECT
  MIN(percentile_rank) AS percentile
FROM percentile_ranks
WHERE avg_temperature >= 37.5;