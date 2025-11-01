WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admission_location,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(a.admission_location) LIKE '%emergency%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_location,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_los_le_7_days,
  COUNT(*) AS n_admissions
FROM
  cohort
GROUP BY
  discharge_location
ORDER BY
  n_admissions DESC;