WITH female_icustays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),

hfnc_stays AS (
  -- Identify stays where high-flow nasal cannula was recorded
  SELECT DISTINCT
    f.stay_id
  FROM
    female_icustays AS f
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON f.stay_id = ce.stay_id
      AND ce.charttime BETWEEN f.intime AND f.outtime
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%high flow nasal cannula%'
),

gcs_events AS (
  -- Extract GCS total measurements on ICU day 2 or later
  SELECT
    ce.valuenum
  FROM
    hfnc_stays AS h
    JOIN female_icustays AS f
      ON h.stay_id = f.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON f.stay_id = ce.stay_id
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN f.intime AND f.outtime
      -- ICU day 2 or later
      AND ce.charttime >= TIMESTAMP_ADD(f.intime, INTERVAL 2 DAY)
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    -- Assuming the GCS total label contains 'Glasgow Coma Score' or similar
    LOWER(di.label) LIKE '%glasgow coma score%'
)

SELECT
  -- Approximate median (50th percentile) of all GCS total values
  APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median_gcs_total
FROM
  gcs_events;