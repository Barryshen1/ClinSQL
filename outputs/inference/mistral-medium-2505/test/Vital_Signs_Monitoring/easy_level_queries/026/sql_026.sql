WITH male_patients_39_49 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 39 AND 49
),

icu_stays_with_patients AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    male_patients_39_49 p ON icu.subject_id = p.subject_id
),

respiratory_rates AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays_with_patients icu ON ce.subject_id = icu.subject_id
    AND ce.hadm_id = icu.hadm_id
    AND ce.stay_id = icu.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Respiratory Rate'
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
)

SELECT
  MIN(valuenum) AS min_respiratory_rate
FROM
  respiratory_rates;