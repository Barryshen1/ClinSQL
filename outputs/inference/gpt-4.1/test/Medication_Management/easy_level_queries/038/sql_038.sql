SELECT
  quantiles[OFFSET(1)] AS duration_25th_percentile_days,
  quantiles[OFFSET(3)] AS duration_75th_percentile_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quantiles
  FROM (
    SELECT
      p.subject_id,
      pr.hadm_id,
      pr.starttime,
      pr.stoptime,
      DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) + 1 AS duration_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` p
      ON pr.subject_id = p.subject_id
    WHERE
      LOWER(pr.drug) LIKE '%digoxin%'
      AND p.gender = 'M'
      AND p.anchor_age BETWEEN 36 AND 46
      AND pr.starttime IS NOT NULL
      AND pr.stoptime IS NOT NULL
      AND DATE(pr.stoptime) >= DATE(pr.starttime)
  )
);