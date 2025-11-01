WITH amio_durations AS (
  SELECT
    TIMESTAMP_DIFF(prescriptions.stoptime, prescriptions.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS patients
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS prescriptions
      USING(subject_id, hadm_id)
  WHERE
    patients.gender = 'M'
    AND patients.anchor_age BETWEEN 62 AND 72
    AND LOWER(prescriptions.drug) LIKE '%amiodarone%'
    AND prescriptions.starttime IS NOT NULL
    AND prescriptions.stoptime IS NOT NULL
    AND TIMESTAMP_DIFF(prescriptions.stoptime, prescriptions.starttime, DAY) > 0
)
SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_days,
  quantiles[OFFSET(1)]           AS q1_days,
  quantiles[OFFSET(3)]           AS q3_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM
    amio_durations
);