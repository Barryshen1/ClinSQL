WITH female_icu_stays AS (
  SELECT
    icu.stay_id,
    icu.subject_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 37 AND 47
),
temperature_itemids AS (
  SELECT
    itemid,
    label,
    unitname
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%temperature%'
),
temps AS (
  SELECT
    ce.stay_id,
    -- Convert Fahrenheit to Celsius if needed
    CASE
      WHEN LOWER(di.unitname) LIKE '%f%' AND ce.valuenum IS NOT NULL THEN (ce.valuenum - 32) * 5.0/9.0
      WHEN LOWER(di.unitname) LIKE '%c%' THEN ce.valuenum
      ELSE NULL
    END AS temp_c
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN temperature_itemids di
      ON ce.itemid = di.itemid
    JOIN female_icu_stays fis
      ON ce.stay_id = fis.stay_id
  WHERE
    ce.valuenum IS NOT NULL
)
, mean_temp_per_stay AS (
  SELECT
    stay_id,
    AVG(temp_c) AS mean_temp_c
  FROM
    temps
  WHERE
    temp_c BETWEEN 25 AND 45 -- plausible human temperatures in Celsius
  GROUP BY
    stay_id
)
SELECT
  PERCENTILE_CONT(mean_temp_c, 0.75) OVER() AS percentile_75_mean_temp_c
FROM
  mean_temp_per_stay
;