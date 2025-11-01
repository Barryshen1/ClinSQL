WITH female_90_plus_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 300  -- proxy for age ≥ 90
),
thiazide_prescriptions AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
  FROM
    female_90_plus_adms f
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON f.subject_id = p.subject_id
     AND f.hadm_id    = p.hadm_id
  WHERE
    p.starttime >= f.admittime
    AND p.starttime <  f.dischtime
    AND LOWER(p.drug) IN UNNEST([
      'hydrochlorothiazide',
      'chlorthalidone',
      'indapamide',
      'metolazone'
    ])
    AND DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) > 0
)
SELECT
  quantiles[OFFSET(1)] AS q1_days,
  quantiles[OFFSET(3)] AS q3_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM
    thiazide_prescriptions
);