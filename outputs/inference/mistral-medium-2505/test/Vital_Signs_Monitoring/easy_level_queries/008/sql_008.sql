WITH male_patients_52_62 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),

icu_stays_with_intime AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    s.stay_id,
    s.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` s
  ON
    a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_patients_52_62)
),

respiratory_rates AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays_with_intime s
  ON
    c.subject_id = s.subject_id
    AND c.hadm_id = s.hadm_id
    AND c.stay_id = s.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
  ON
    c.itemid = d.itemid
  WHERE
    d.label = 'Respiratory Rate'
    AND TIMESTAMP_DIFF(c.charttime, s.intime, DAY) >= 2
    AND c.valuenum IS NOT NULL
)

SELECT
  MAX(valuenum) AS max_respiratory_rate
FROM
  respiratory_rates
WHERE
  valuenum IS NOT NULL;