WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND a.dischtime IS NOT NULL
),

los_aggregates AS (
  SELECT
    CASE WHEN hospital_expire_flag = 1 THEN 'Died' ELSE 'Alive' END AS discharge_status,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge7,
    SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS los_ge14,
    APPROX_QUANTILES(los_days, 100)[OFFSET(10)] AS percentile_10day_los
  FROM
    patient_admissions
  GROUP BY
    discharge_status
),

percentile_ranks AS (
  SELECT
    discharge_status,
    total_patients,
    los_ge7,
    los_ge14,
    percentile_10day_los,
    PERCENT_RANK() OVER (ORDER BY percentile_10day_los) AS percentile_rank_10day
  FROM
    los_aggregates
)

SELECT
  discharge_status,
  total_patients,
  ROUND(los_ge7 / total_patients, 4) AS prop_los_ge7,
  ROUND(los_ge14 / total_patients, 4) AS prop_los_ge14,
  ROUND(percentile_rank_10day, 4) AS avg_percentile_rank_10day
FROM
  percentile_ranks
ORDER BY
  discharge_status;