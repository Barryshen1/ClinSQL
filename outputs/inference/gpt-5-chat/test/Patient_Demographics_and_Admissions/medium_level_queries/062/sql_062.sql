WITH base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.dischtime IS NOT NULL
)
, categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      WHEN UPPER(discharge_location) LIKE '%SKILLED NURSING%' 
        OR UPPER(discharge_location) LIKE '%REHAB%' 
        OR UPPER(discharge_location) LIKE '%LONG TERM ACUTE CARE%' THEN 'SNF/rehab/LTACH'
      ELSE 'Other'
    END AS discharge_group
  FROM base
)
SELECT
  discharge_group,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge_7_count,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS proportion_los_ge_7,
  -- Approximate 14th percentile LOS in days
  APPROX_QUANTILES(los_days, 100)[OFFSET(14)] AS los_days_p14
FROM categorized
WHERE discharge_group IN ('Home', 'SNF/rehab/LTACH', 'In-hospital death')
GROUP BY discharge_group
ORDER BY discharge_group;