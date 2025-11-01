WITH cohort AS (
  SELECT
    p.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON p.subject_id = adm.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),

dapt_orders AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM
    cohort AS c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON pr.subject_id = c.subject_id
      AND pr.hadm_id     = c.hadm_id
  WHERE
    pr.drug = 'DAPT'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime  IS NOT NULL
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) > 0
)

SELECT
  quantiles[OFFSET(1)] AS p25_duration_days,
  quantiles[OFFSET(3)] AS p75_duration_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM
    dapt_orders
);