WITH prescription_durations AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime > p.starttime
    AND (
      LOWER(p.drug) LIKE '%amlodipine%'
      OR LOWER(p.drug) LIKE '%nifedipine%'
      OR LOWER(p.drug) LIKE '%felodipine%'
      OR LOWER(p.drug) LIKE '%nicardipine%'
      OR LOWER(p.drug) LIKE '%nisoldipine%'
    )
),
ranked AS (
  SELECT
    duration_days,
    ROW_NUMBER() OVER (ORDER BY duration_days) AS rn,
    COUNT(*) OVER () AS total
  FROM prescription_durations
)
SELECT
  AVG(duration_days) AS median_duration_days
FROM ranked
WHERE rn IN (FLOOR((total + 1) / 2), CEIL((total + 1) / 2));