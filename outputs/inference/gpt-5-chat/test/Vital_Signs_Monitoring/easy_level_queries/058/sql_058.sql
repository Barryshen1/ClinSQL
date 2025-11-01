WITH temp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(unitname) IN ('degf', '°f', 'fahrenheit')
     OR unitname = '°F'
),
stay_min_temp AS (
  SELECT
    ce.stay_id,
    MIN(ce.valuenum) AS min_temp_f
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN temp_itemids ti
    ON ce.itemid = ti.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
stay_with_patients AS (
  SELECT
    smt.min_temp_f
  FROM stay_min_temp smt
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON smt.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
)
SELECT
  APPROX_QUANTILES(min_temp_f, 2)[OFFSET(1)] AS median_min_temp_f
FROM stay_with_patients;