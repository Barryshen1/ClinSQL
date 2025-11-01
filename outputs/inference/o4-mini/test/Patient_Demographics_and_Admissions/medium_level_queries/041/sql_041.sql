WITH cohort AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 88 AND 98
    AND a.admission_type = 'ELECTIVE'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
categorized AS (
  SELECT
    los_days,
    hospital_expire_flag,
    discharge_location,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%snf%'
        OR LOWER(discharge_location) LIKE '%rehab%'
        OR LOWER(discharge_location) LIKE '%ltach%' THEN 'SNF/Rehab/LTACH'
      WHEN LOWER(discharge_location) LIKE 'home%' THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM cohort
)
SELECT
  discharge_outcome,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days), 2) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  ROUND(
    100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*)
  , 2) AS pct_los_le_7_days
FROM categorized
WHERE discharge_outcome IS NOT NULL
GROUP BY discharge_outcome
ORDER BY
  CASE discharge_outcome
    WHEN 'Home' THEN 1
    WHEN 'SNF/Rehab/LTACH' THEN 2
    WHEN 'In-hospital death' THEN 3
    ELSE 4
  END;