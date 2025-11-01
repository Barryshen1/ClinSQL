WITH first_admissions AS (
  SELECT
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) WITHIN GROUP (ORDER BY los_days) - PERCENTILE_CONT(los_days, 0.25) WITHIN GROUP (ORDER BY los_days) AS iqr
FROM
  first_admissions;