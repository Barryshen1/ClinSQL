WITH male_icu_patients AS (
  -- Get male patients with ICU stays
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
),

ph_measurements AS (
  -- Get arterial blood gas pH measurements (itemid 1127)
  SELECT
    m.subject_id,
    m.stay_id,
    ce.charttime,
    ce.valuenum AS ph_value
  FROM
    male_icu_patients m
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    m.subject_id = ce.subject_id AND m.stay_id = ce.stay_id
  WHERE
    ce.itemid = 1127  -- pH in arterial blood gas
    AND ce.valuenum IS NOT NULL
),

peak_ph_per_patient AS (
  -- Get the peak pH value for each patient
  SELECT
    subject_id,
    MAX(ph_value) AS peak_ph
  FROM
    ph_measurements
  GROUP BY
    subject_id
)

-- Calculate the IQR (25th and 75th percentiles) of peak pH values
SELECT
  PERCENTILE_CONT(peak_ph, 0.25) OVER() AS q1,
  PERCENTILE_CONT(peak_ph, 0.75) OVER() AS q3,
  PERCENTILE_CONT(peak_ph, 0.75) OVER() - PERCENTILE_CONT(peak_ph, 0.25) OVER() AS iqr
FROM
  peak_ph_per_patient
LIMIT 1;