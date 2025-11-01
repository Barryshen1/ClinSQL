WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'TRANSFER FROM OTHER FACILITY'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
),
grouped_data AS (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location IN ('HOME') THEN 'Discharged home'
      WHEN a.discharge_location IN ('SNF', 'HOME HEALTH CARE', 'REHAB', 'LONG TERM CARE FACILITY', 'LTACH', 'SKILLED NURSING FACILITY') THEN 'Discharged to facility'
      ELSE 'Other'
    END AS discharge_group,
    los_days
  FROM
    cohort a
)
SELECT
  discharge_group,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(STDDEV(los_days), 2) AS std_los,
  ROUND(AVG(CASE WHEN los_days <= 5 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_rank_5day_percent
FROM
  grouped_data
WHERE
  discharge_group IN ('Discharged home', 'Discharged to facility', 'In-hospital death')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;