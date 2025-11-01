SELECT
  PERCENTILE_CONT(duration_days, 0.5) OVER() AS median_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    pr.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age >= 90
    AND p.anchor_age <= 100
    AND LOWER(pr.drug) IN ('spironolactone', 'eplerenone')
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
)
LIMIT 1;