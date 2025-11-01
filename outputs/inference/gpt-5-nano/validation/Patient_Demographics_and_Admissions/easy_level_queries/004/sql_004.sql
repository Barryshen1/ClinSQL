WITH cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 70 AND 80
),

first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (
      PARTITION BY a.subject_id
      ORDER BY a.admittime ASC
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN cohort AS c
    ON a.subject_id = c.subject_id
  WHERE a.dischtime IS NOT NULL
)

SELECT
  STDDEV_POP(los_days) AS sd_los_days
FROM (
  SELECT
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM first_admissions
  WHERE rn = 1
);