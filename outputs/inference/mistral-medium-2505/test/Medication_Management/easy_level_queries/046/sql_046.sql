WITH male_inpatients_90_100 AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),

prescriptions_with_duration AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    male_inpatients_90_100 m
  ON
    p.subject_id = m.subject_id AND p.hadm_id = m.hadm_id
  WHERE
    (LOWER(p.drug) LIKE '%spironolactone%' OR LOWER(p.drug) LIKE '%eplerenone%')
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(duration_days, 0.5) OVER() AS median_duration_days
FROM
  prescriptions_with_duration
LIMIT 1;