WITH eligible_prescriptions AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.hadm_id = adm.hadm_id AND p.subject_id = adm.subject_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) BETWEEN 90 AND 100
    AND (
      LOWER(p.drug) LIKE '%thiazide%'
      OR LOWER(p.drug) LIKE '%chlorthalidone%'
      OR LOWER(p.drug) LIKE '%indapamide%'
      OR LOWER(p.drug) LIKE '%metolazone%'
    )
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
),
quartiles AS (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS q_arr
  FROM
    eligible_prescriptions
)
SELECT
  q_arr[OFFSET(1)] AS q1_days,
  q_arr[OFFSET(3)] AS q3_days,
  q_arr[OFFSET(3)] - q_arr[OFFSET(1)] AS iqr_days
FROM
  quartiles;