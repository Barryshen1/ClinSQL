WITH female_medical_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    AND a.dischtime IS NOT NULL
),

los_stats AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge7_count,
    PERCENTILE_CONT(los_days, 0.5) OVER() AS median_los,
    PERCENTILE_CONT(los_days, 0.75) OVER() AS p75_los,
    PERCENTILE_CONT(los_days, 0.9) OVER() AS p90_los,
    PERCENTILE_CONT(los_days, 0.95) OVER() AS p95_los
  FROM
    female_medical_admissions
  GROUP BY
    hospital_expire_flag
),

percentile_ranks AS (
  SELECT
    los_days,
    PERCENT_RANK() OVER (ORDER BY los_days) AS percentile
  FROM
    female_medical_admissions
)

SELECT
  CASE
    WHEN hospital_expire_flag = 0 THEN 'Discharged Alive'
    WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
  END AS discharge_status,
  total_patients,
  los_ge7_count,
  ROUND(los_ge7_count / total_patients * 100, 2) AS proportion_los_ge7_percent,
  (SELECT percentile FROM percentile_ranks WHERE los_days = 7 LIMIT 1) AS percentile_rank_7day_los
FROM
  los_stats
ORDER BY
  hospital_expire_flag;