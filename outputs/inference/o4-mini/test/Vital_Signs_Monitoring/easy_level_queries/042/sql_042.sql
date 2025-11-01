WITH rr_events AS (
  -- Select all respiratory rate measurements with numeric values
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
  ON
    ce.itemid = di.itemid
  WHERE
    di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
),
max_rr_per_stay AS (
  -- Compute the maximum RR per ICU stay
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    MAX(valuenum) AS max_rr
  FROM
    rr_events
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
),
eligible_stays AS (
  -- Identify ICU stays for female patients aged 63–73
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON
    icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
),
filtered_max_rr AS (
  -- Keep only max RR values for eligible stays
  SELECT
    m.max_rr
  FROM
    max_rr_per_stay AS m
  JOIN
    eligible_stays AS e
  ON
    m.subject_id = e.subject_id
    AND m.hadm_id = e.hadm_id
    AND m.stay_id = e.stay_id
)
-- Compute the sample standard deviation of the per-stay maxima
SELECT
  STDDEV_SAMP(max_rr) AS sd_max_respiratory_rate
FROM
  filtered_max_rr;