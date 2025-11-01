WITH prescription_durations AS (
  SELECT
    DATE_DIFF(p.stoptime, p.starttime, 'DAY') AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON
    p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 81 AND 91
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
    AND p.stoptime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS percentile_25
FROM
  prescription_durations;