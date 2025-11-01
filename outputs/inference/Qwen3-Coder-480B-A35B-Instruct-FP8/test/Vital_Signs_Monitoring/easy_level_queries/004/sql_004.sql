WITH temp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND linksto = 'chartevents'
),
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 37 AND 47
),
icu_stays_with_temp AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_temp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN filtered_patients fp ON ce.subject_id = fp.subject_id
  JOIN temp_items ti ON ce.itemid = ti.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 45
  GROUP BY ce.stay_id
)
SELECT
  APPROX_QUANTILES(mean_temp, 100)[OFFSET(75)] AS percentile_75_mean_temperature
FROM icu_stays_with_temp;