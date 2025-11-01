WITH eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
),
amio_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.pharmacy_id,
    pr.starttime,
    pr.stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),
single_amio_admissions AS (
  SELECT
    ep.subject_id,
    ep.hadm_id,
    MIN(ap.starttime) AS starttime,
    MIN(ap.stoptime) AS stoptime
  FROM
    eligible_patients ep
    INNER JOIN amio_prescriptions ap
      ON ep.subject_id = ap.subject_id
      AND ep.hadm_id = ap.hadm_id
  GROUP BY
    ep.subject_id,
    ep.hadm_id
  HAVING
    COUNT(DISTINCT ap.pharmacy_id) = 1
),
durations AS (
  SELECT
    subject_id,
    hadm_id,
    DATE_DIFF(DATE(stoptime), DATE(starttime), DAY) + 1 AS duration_days
  FROM
    single_amio_admissions
  WHERE
    DATE_DIFF(DATE(stoptime), DATE(starttime), DAY) >= 0
)
SELECT
  quantiles[OFFSET(1)] AS iqr_25th_percentile_days,
  quantiles[OFFSET(3)] AS iqr_75th_percentile_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM
    durations
);