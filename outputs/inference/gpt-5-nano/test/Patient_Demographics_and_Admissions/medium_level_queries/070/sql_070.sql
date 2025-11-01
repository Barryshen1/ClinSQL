WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    a.hospital_expire_flag,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE (p.gender = 'M' OR p.gender = 'Male')
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type = 'EMERGENCY'
    AND (
       a.discharge_location IN ('Home','Hospice')
       OR a.deathtime IS NOT NULL
       OR a.hospital_expire_flag = 1
    )
),
lifespan AS (
  SELECT
    CASE
      WHEN discharge_location = 'Home' THEN 'Home'
      WHEN discharge_location = 'Hospice' THEN 'Hospice'
      WHEN deathtime IS NOT NULL OR hospital_expire_flag = 1 THEN 'In-hospital death'
    END AS group_label,
    -- end time: prefer discharge time; fall back to death time if needed
    TIMESTAMP_DIFF(COALESCE(dischtime, deathtime), admittime, SECOND) / 86400.0 AS los_days
  FROM admissions_filtered
  WHERE
    CASE
      WHEN discharge_location = 'Home' THEN 'Home'
      WHEN discharge_location = 'Hospice' THEN 'Hospice'
      WHEN deathtime IS NOT NULL OR hospital_expire_flag = 1 THEN 'In-hospital death'
    END IS NOT NULL
),
stats AS (
  SELECT
    group_label,
    AVG(los_days) AS mean_los_days,
    100.0 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*) AS pct_le_10_days
  FROM lifespan
  GROUP BY group_label
),
quantiles AS (
  SELECT
    group_label,
    APPROX_QUANTILES(los_days, 101) AS qa
  FROM lifespan
  GROUP BY group_label
),
final AS (
  SELECT
    s.group_label,
    s.mean_los_days,
    q.qa[OFFSET(50)] AS median_los_days,
    q.qa[OFFSET(75)] AS p75_los_days,
    q.qa[OFFSET(90)] AS p90_los_days,
    s.pct_le_10_days
  FROM stats s
  JOIN quantiles q ON s.group_label = q.group_label
)
SELECT *
FROM final
ORDER BY group_label;