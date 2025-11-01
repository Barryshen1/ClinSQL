WITH
-- Get male patients aged 35-45
male_patients_35_45 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 35 AND 45
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    male_patients_35_45 p ON s.subject_id = p.subject_id
),

-- Get respiratory rate measurements (itemid 220210 is respiratory rate)
respiratory_rates AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS respiratory_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    ce.stay_id IN (SELECT stay_id FROM icu_stays)
    AND di.label = 'Respiratory Rate'  -- or itemid = 220210 if label is not reliable
    AND ce.valuenum IS NOT NULL
),

-- Calculate max respiratory rate per ICU stay
max_rr_per_stay AS (
  SELECT
    stay_id,
    MAX(respiratory_rate) AS max_respiratory_rate
  FROM
    respiratory_rates
  GROUP BY
    stay_id
)

-- Get the minimum of these maximum values
SELECT
  MIN(max_respiratory_rate) AS min_of_max_respiratory_rates
FROM
  max_rr_per_stay;