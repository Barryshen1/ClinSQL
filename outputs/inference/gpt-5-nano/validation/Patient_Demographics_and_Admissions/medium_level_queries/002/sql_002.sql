WITH admissions_filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.services` AS s
    ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  WHERE LOWER(s.curr_service) LIKE '%medicine%'
    AND p.gender = 'M'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
),
eligible AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    discharge_location,
    hospital_expire_flag,
    age_at_adm,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%facility%' OR
           LOWER(discharge_location) LIKE '%snf%' OR
           LOWER(discharge_location) LIKE '%rehab%' OR
           LOWER(discharge_location) LIKE '%nursing%' THEN 'Facility'
      ELSE NULL
    END AS discharge_group
  FROM admissions_filtered
  WHERE age_at_adm BETWEEN 59 AND 69
    AND dischtime IS NOT NULL
    AND admittime < dischtime
    AND CASE
          WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
          ELSE discharge_location
        END IS NOT NULL
),
los_data AS (
  SELECT
    discharge_group,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM eligible
  WHERE discharge_group IS NOT NULL
),
grouped AS (
  SELECT
    discharge_group,
    AVG(los_days) AS mean_los_days,
    APPROX_QUANTILES(los_days, 100) AS quantiles,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS count_le10,
    COUNT(*) AS total
  FROM los_data
  GROUP BY discharge_group
)
SELECT
  discharge_group,
  mean_los_days,
  quantiles[OFFSET(25)] AS p25_los_days,
  quantiles[OFFSET(50)] AS p50_los_days,
  quantiles[OFFSET(75)] AS p75_los_days,
  quantiles[OFFSET(90)] AS p90_los_days,
  SAFE_DIVIDE(count_le10, total) * 100 AS pct_le10
FROM grouped
ORDER BY discharge_group;