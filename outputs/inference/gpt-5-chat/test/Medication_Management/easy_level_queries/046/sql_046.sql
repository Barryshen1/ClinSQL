WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
spiron_eplerenone_rx AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    cohort c
    ON pr.subject_id = c.subject_id
    AND pr.hadm_id = c.hadm_id
  WHERE
    pr.drug IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%spironolactone%'
      OR LOWER(pr.drug) LIKE '%eplerenone%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(duration_days, 0.5) OVER() AS median_duration_days
FROM
  spiron_eplerenone_rx
WHERE
  duration_days > 0;