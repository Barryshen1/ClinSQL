WITH RankedAdmissions AS (
  -- First, join patients with their admissions and rank the admissions chronologically
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER(PARTITION BY p.subject_id ORDER BY a.admittime ASC) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
)
-- Then, calculate the standard deviation of LOS for the specified cohort
SELECT
  STDDEV(DATETIME_DIFF(dischtime, admittime, DAY)) AS stddev_los_days
FROM
  RankedAdmissions
WHERE
  gender = 'F'
  AND anchor_age BETWEEN 70 AND 80
  AND admission_rank = 1; -- Filter for first admissions only;