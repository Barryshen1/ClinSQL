WITH lab_scores AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COUNTIF(le.flag = 'abnormal') AS critical_lab_count_48h,
    COUNT(le.labevent_id) AS total_lab_count_48h,
    SAFE_DIVIDE(COUNTIF(le.flag = 'abnormal'), COUNT(le.labevent_id)) AS critical_lab_rate_48h
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.subject_id = le.subject_id
    AND a.hadm_id = le.hadm_id
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    p.subject_id, a.hadm_id, p.gender, p.anchor_age,
    a.admittime, a.dischtime, a.hospital_expire_flag
),
p95_cutoff AS (
  SELECT
    PERCENTILE_CONT(critical_lab_count_48h, 0.95) OVER() AS cutoff_value
  FROM lab_scores
  WHERE gender = 'F' AND anchor_age BETWEEN 55 AND 65
  LIMIT 1
),
top_tier AS (
  SELECT ls.*
  FROM lab_scores ls
  CROSS JOIN p95_cutoff pc
  WHERE ls.gender = 'F'
    AND ls.anchor_age BETWEEN 55 AND 65
    AND ls.critical_lab_count_48h >= pc.cutoff_value
),
metrics AS (
  SELECT
    'Top Tier (Female 55-65, >=95th percentile lab instability)' AS cohort,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(critical_lab_rate_48h) AS avg_critical_lab_rate
  FROM top_tier
  UNION ALL
  SELECT
    'General Inpatients' AS cohort,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(critical_lab_rate_48h) AS avg_critical_lab_rate
  FROM lab_scores
)
SELECT * FROM metrics;