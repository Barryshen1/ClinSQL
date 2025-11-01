WITH temp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%' AND (unitname = '°F' OR unitname = 'degF' OR unitname = 'F')
),
male_74_84 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 74 AND 84
),
min_temp_per_stay AS (
  SELECT
    ce.stay_id,
    MIN(ce.valuenum) AS min_temp_f
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN temp_itemids ti ON ce.itemid = ti.itemid
  INNER JOIN male_74_84 p ON ce.subject_id = p.subject_id
  WHERE ce.valueuom = '°F'
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
)
SELECT
  APPROX_QUANTILES(min_temp_f, 2)[OFFSET(1)] AS median_min_temp_f
FROM min_temp_per_stay
;