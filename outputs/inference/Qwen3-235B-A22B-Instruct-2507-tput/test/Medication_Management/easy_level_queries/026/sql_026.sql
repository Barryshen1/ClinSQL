SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
  ON
    pr.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.starttime <= pr.stoptime
    AND LOWER(pr.drug) IN (
      'amlodipine', 'nifedipine', 'felodipine', 'nicardipine',
      'isradipine', 'barnidipine', 'lercanidipine', 'clevidipine',
      'nitrendipine', 'niguldipine'
    )
);