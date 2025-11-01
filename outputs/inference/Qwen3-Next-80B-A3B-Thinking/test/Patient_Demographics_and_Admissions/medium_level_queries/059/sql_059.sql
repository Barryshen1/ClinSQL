WITH cohort AS (
  SELECT
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_location IN ('TRANSFER FROM HOSP/OTHER FACILITY', 'TRANSFER FROM OTHER HOSPITAL')
    AND a.discharge_location IN ('HOME', 'HOSPICE', 'DEATH')
)
SELECT
  discharge_location,
  COUNTIF(los_days >= 7) / COUNT(*) AS proportion
FROM
  cohort
GROUP BY
  discharge_location
UNION ALL
SELECT
  '7th_percentile' AS discharge_location,
  PERCENTILE_CONT(0.07) WITHIN GROUP (ORDER BY los_days) AS proportion
FROM
  cohort;