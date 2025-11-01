WITH amiodarone_prescriptions AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON pr.hadm_id = a.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    LOWER(pr.drug) LIKE '%amiodarone%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) > 0
)

SELECT
  quantiles[OFFSET(1)] AS p25_duration_days,
  quantiles[OFFSET(3)] AS p75_duration_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_duration_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM
    amiodarone_prescriptions
);