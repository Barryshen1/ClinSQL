WITH admissions_with_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    p.gender,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
filtered_admissions AS (
  SELECT
    hadm_id,
    discharge_location,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    admissions_with_age
  WHERE
    age BETWEEN 68 AND 78
)
SELECT
  discharge_location,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS stddev_los,
  AVG(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100 AS percent_los_le_7_days
FROM
  filtered_admissions
GROUP BY
  discharge_location
ORDER BY
  discharge_location;