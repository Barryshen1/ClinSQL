WITH respiratory_rate_events AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    ce.charttime,
    ce.valuenum AS respiratory_rate,
    p.anchor_year - p.anchor_age AS birth_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
  WHERE
    ce.itemid IN (220210, 670, 224690) -- respiratory rate itemids
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100 -- reasonable range for respiratory rate
),
first_rr_per_patient AS (
  SELECT
    subject_id,
    gender,
    anchor_year,
    anchor_age,
    birth_year,
    charttime,
    respiratory_rate,
    TIMESTAMP_DIFF(charttime, DATE(birth_year, 1, 1), YEAR) AS age_at_event
  FROM (
    SELECT
      rre.*,
      ROW_NUMBER() OVER (PARTITION BY rre.subject_id ORDER BY rre.charttime ASC) AS rn
    FROM
      respiratory_rate_events rre
  )
  WHERE
    rn = 1 -- first event per patient
),
filtered_patients AS (
  SELECT
    subject_id,
    respiratory_rate,
    age_at_event
  FROM
    first_rr_per_patient
  WHERE
    gender = 'M'
    AND age_at_event BETWEEN 51 AND 61
)
SELECT
  STDDEV(respiratory_rate) AS sd_respiratory_rate
FROM
  filtered_patients;