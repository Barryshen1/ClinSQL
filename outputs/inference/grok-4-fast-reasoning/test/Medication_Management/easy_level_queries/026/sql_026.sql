SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS p25_duration_days
FROM (
  SELECT
    (TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.subject_id = pr.subject_id
    AND a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND pr.drug IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.starttime < pr.stoptime
    AND (
      LOWER(pr.drug) LIKE '%amlodipine%'
      OR LOWER(pr.drug) LIKE '%nifedipine%'
      OR LOWER(pr.drug) LIKE '%felodipine%'
      OR LOWER(pr.drug) LIKE '%nicardipine%'
      OR LOWER(pr.drug) LIKE '%nimodipine%'
      OR LOWER(pr.drug) LIKE '%nisoldipine%'
      OR LOWER(pr.drug) LIKE '%isradipine%'
    )
);