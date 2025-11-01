WITH eligible_patients AS (
  SELECT
    p.subject_id,
    p.anchor_year,
    p.anchor_age,
    i.stay_id,
    i.intime,
    (p.anchor_year - p.anchor_age) AS birth_year,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
),
filtered_patients AS (
  SELECT
    subject_id,
    stay_id,
    intime,
    age_at_admission
  FROM
    eligible_patients
  WHERE
    age_at_admission BETWEEN 74 AND 84
),
temperature_data AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS temperature_f
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.category = 'Temperature'
    AND di.unitname = '°F'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 95 AND 105
),
min_temp_per_stay AS (
  SELECT
    t.stay_id,
    MIN(t.temperature_f) AS min_temperature
  FROM
    temperature_data t
  GROUP BY
    t.stay_id
),
eligible_stays_with_min_temp AS (
  SELECT
    fp.subject_id,
    fp.stay_id,
    fp.age_at_admission,
    mt.min_temperature
  FROM
    filtered_patients fp
  INNER JOIN
    min_temp_per_stay mt
    ON fp.stay_id = mt.stay_id
)
SELECT
  APPROX_QUANTILES(min_temperature, 100)[OFFSET(50)] AS median_min_temperature
FROM
  eligible_stays_with_min_temp;