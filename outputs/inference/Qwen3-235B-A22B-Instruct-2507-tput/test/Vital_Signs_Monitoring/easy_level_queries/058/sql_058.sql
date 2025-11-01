WITH temp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%'
    AND LOWER(category) = 'vital signs'
),
stay_min_temp AS (
  SELECT
    ce.stay_id,
    MIN(ce.valuenum) AS min_temp_f
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN temp_itemids ti ON ce.itemid = ti.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON ce.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND ce.valuenum IS NOT NULL
    AND LOWER(ce.valueuom) = 'f'
    AND ce.charttime >= ie.intime
    AND ce.charttime <= ie.outtime
  GROUP BY ce.stay_id
)
SELECT
  APPROX_QUANTILES(min_temp_f, 100)[OFFSET(50)] AS median_min_temperature_f
FROM stay_min_temp;