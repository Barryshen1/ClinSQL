WITH hr_events AS (
  SELECT
    p.subject_id,
    ce.stay_id,
    ce.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ce.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ce.subject_id = icu.subject_id
      AND ce.hadm_id = icu.hadm_id
      AND ce.stay_id = icu.stay_id
  WHERE
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),
patient_max_hr AS (
  SELECT
    subject_id,
    MAX(heart_rate) AS max_hr
  FROM
    hr_events
  GROUP BY
    subject_id
),
quantiles AS (
  SELECT
    APPROX_QUANTILES(max_hr, 4) AS q_array
  FROM
    patient_max_hr
)
SELECT
  q_array[OFFSET(1)] AS hr_p25,
  q_array[OFFSET(3)] AS hr_p75,
  q_array[OFFSET(3)] - q_array[OFFSET(1)] AS hr_iqr
FROM
  quantiles;