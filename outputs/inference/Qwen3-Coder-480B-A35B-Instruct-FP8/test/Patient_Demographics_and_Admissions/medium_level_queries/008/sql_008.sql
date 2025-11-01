WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'OTHER FACILITY') THEN 'Facility'
      WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Death'
      ELSE 'Other'
    END AS discharge_group
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
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 52 AND 62
    AND a.admission_type != 'ELECTIVE'
    AND s.curr_service = 'MED'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
ranked_los AS (
  SELECT
    *,
    PERCENT_RANK() OVER (PARTITION BY discharge_group ORDER BY los_days) AS percentile_rank,
    CASE WHEN los_days <= 7 THEN 1 ELSE 0 END AS leq_7_flag
  FROM
    cohort
  WHERE
    discharge_group IN ('Home', 'Facility', 'In-Hospital Death')
)
SELECT
  discharge_group,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  AVG(percentile_rank) * 100 AS percentile_rank_7_days
FROM
  ranked_los
GROUP BY
  discharge_group
ORDER BY
  discharge_group;