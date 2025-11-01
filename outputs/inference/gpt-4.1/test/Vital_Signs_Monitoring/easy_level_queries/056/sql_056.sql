WITH male_46_56 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 46 AND 56
),
temp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND unitname = '°F'
),
temps_first_24h AS (
  SELECT
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN male_46_56 p ON ce.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
    AND ce.stay_id = icu.stay_id
  INNER JOIN temp_itemids ti ON ce.itemid = ti.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
)
SELECT
  APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median_temperature_F
FROM temps_first_24h;