WITH thiazide_prescriptions AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND LOWER(pr.drug) LIKE '%thiazide%'
      OR LOWER(pr.drug) LIKE '%chlorthalidone%'
      OR LOWER(pr.drug) LIKE '%indapamide%'
      OR LOWER(pr.drug) LIKE '%metolazone%'
      OR LOWER(pr.drug) LIKE '%hydrochlorothiazide%'
)
SELECT
  quantiles[OFFSET(1)] AS iqr_25th_percentile_days,
  quantiles[OFFSET(3)] AS iqr_75th_percentile_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM
    thiazide_prescriptions
  WHERE
    duration_days > 0
);