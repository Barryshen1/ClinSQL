SELECT
  PERCENTILE_CONT(duration_days, 0.5) OVER() AS median_duration_days
FROM (
  SELECT
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pa
  ON
    pr.subject_id = pa.subject_id
  WHERE
    pa.gender = 'M'
    AND pa.anchor_age BETWEEN 58 AND 68
    AND (
      LOWER(pr.drug) LIKE '%heparin%'
      OR LOWER(pr.drug) LIKE '%enoxaparin%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) >= 0
);