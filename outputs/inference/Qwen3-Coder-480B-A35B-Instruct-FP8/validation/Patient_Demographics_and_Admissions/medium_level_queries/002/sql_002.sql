WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.services` s
  ON
    a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND s.curr_service = 'MED'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Died in Hospital'
      WHEN discharge_location LIKE 'HOME%' THEN 'Discharged Home'
      ELSE 'Discharged to Facility'
    END AS discharge_category
  FROM
    cohort
)
SELECT
  discharge_category,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_p25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_p50,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS los_p90,
  AVG(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100 AS pct_los_le_10_days
FROM
  discharge_groups
GROUP BY
  discharge_category
ORDER BY
  discharge_category;