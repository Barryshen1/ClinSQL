WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admission_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_location LIKE 'EMERGENCY%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
ranks AS (
  SELECT
    c.*,
    PERCENT_RANK() OVER (PARTITION BY c.hospital_expire_flag ORDER BY c.los_days) AS los_percent_rank
  FROM
    cohort c
)
SELECT
  CASE hospital_expire_flag
    WHEN 0 THEN 'Alive'
    WHEN 1 THEN 'Died'
    ELSE 'Unknown'
  END AS discharge_status,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*) AS prop_los_ge_7,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) / COUNT(*) AS prop_los_ge_14,
  AVG(CASE WHEN los_days = 10 THEN los_percent_rank END) AS percentile_rank_los_10
FROM
  ranks
GROUP BY
  hospital_expire_flag
ORDER BY
  discharge_status;