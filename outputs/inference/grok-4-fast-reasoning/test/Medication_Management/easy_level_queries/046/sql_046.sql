WITH durations AS (
  SELECT
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    pr.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND pr.hadm_id IS NOT NULL
    AND (LOWER(pr.drug) LIKE '%spironolactone%' OR LOWER(pr.drug) LIKE '%eplerenone%')
    AND pr.stoptime IS NOT NULL
    AND pr.starttime < pr.stoptime
)
SELECT
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM
  durations;