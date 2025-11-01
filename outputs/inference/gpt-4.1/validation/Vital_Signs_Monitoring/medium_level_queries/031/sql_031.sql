WITH temp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
),

male_stays AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 67 AND 77
),

temp_measurements AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN temp_itemids ti ON ce.itemid = ti.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 45 -- plausible human temperature range in Celsius
),

first24hr_temps AS (
  SELECT
    ms.stay_id,
    tm.valuenum
  FROM male_stays ms
  JOIN temp_measurements tm
    ON ms.stay_id = tm.stay_id
    AND tm.charttime >= ms.intime
    AND tm.charttime < TIMESTAMP_ADD(ms.intime, INTERVAL 24 HOUR)
),

avg_temp_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_temp
  FROM first24hr_temps
  GROUP BY stay_id
)

SELECT
  SAFE_DIVIDE(COUNTIF(avg_temp <= 36.0), COUNT(*)) AS percentile_36C
FROM avg_temp_per_stay;