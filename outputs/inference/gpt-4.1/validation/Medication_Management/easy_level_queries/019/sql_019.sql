SELECT
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
      LOWER(pr.drug) LIKE '%heparin%'
      OR LOWER(pr.drug) LIKE '%enoxaparin%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) >= 0
);