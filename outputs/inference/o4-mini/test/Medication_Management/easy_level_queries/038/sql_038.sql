WITH digoxin_durations AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- Duration in days, as a floating‐point number
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND)/86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON pr.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    -- Ensure the prescription was during the hospitalization
    AND pr.starttime >= a.admittime
    AND pr.stoptime <= a.dischtime
)
SELECT
  quantiles[OFFSET(25)] AS q1_duration_days,
  quantiles[OFFSET(75)] AS q3_duration_days,
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_days
FROM (
  SELECT
    -- APPROX_QUANTILES returns an array of length 101 for 100 quantiles (0%,1%,...,100%)
    APPROX_QUANTILES(duration_days, 100) AS quantiles
  FROM
    digoxin_durations
);