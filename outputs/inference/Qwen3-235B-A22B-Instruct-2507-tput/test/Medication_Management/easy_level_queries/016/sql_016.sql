SELECT
  APPROX_PERCENTILE(duration_days, 0.25) AS percentile_25_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.route,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  ON
    p.subject_id = pr.subject_id
  WHERE
    p.anchor_age BETWEEN 76 AND 86
    AND p.gender = 'M'
    AND LOWER(pr.drug) LIKE '%nitrate%'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND LOWER(pr.route) IN ('iv', 'intravenous', 'po', 'oral', 'per oral')
);