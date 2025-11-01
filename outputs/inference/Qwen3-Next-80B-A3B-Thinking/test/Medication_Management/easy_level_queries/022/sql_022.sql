WITH durations AS (
  SELECT
    TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON
    p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 59 AND 69
    AND stoptime IS NOT NULL
    AND starttime IS NOT NULL
    AND (
      LOWER(p.drug) LIKE '%amlodipine%'
      OR LOWER(p.drug) LIKE '%nifedipine%'
      OR LOWER(p.drug) LIKE '%felodipine%'
      OR LOWER(p.drug) LIKE '%nicardipine%'
      OR LOWER(p.drug) LIKE '%isradipine%'
      OR LOWER(p.drug) LIKE '%lacidipine%'
      OR LOWER(p.drug) LIKE '%lercanidipine%'
      OR LOWER(p.drug) LIKE '%manidipine%'
      OR LOWER(p.drug) LIKE '%nitrendipine%'
      OR LOWER(p.drug) LIKE '%pranidipine%'
    )
)
SELECT
  PERCENTILE_CONT(duration, 0.5) OVER () AS median_duration
FROM
  durations
LIMIT 1;