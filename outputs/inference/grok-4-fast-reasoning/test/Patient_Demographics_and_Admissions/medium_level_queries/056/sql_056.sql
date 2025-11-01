WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admission_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
)

SELECT
  CASE WHEN hospital_expire_flag = 0 THEN 'Alive' ELSE 'Died' END AS discharge_status,
  COUNT(*) AS n_patients,
  AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0.0 END) AS proportion_los_ge7,
  AVG(CASE WHEN los_days >= 14 THEN 1.0 ELSE 0.0 END) AS proportion_los_ge14,
  AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0.0 END) * 100 AS percentile_rank_10day_los
FROM
  cohort
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;