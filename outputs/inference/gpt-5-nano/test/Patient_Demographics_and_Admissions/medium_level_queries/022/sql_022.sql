WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.admission_type,
    p.anchor_age,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(a.admission_type) LIKE '%transfer%'
    AND a.dischtime IS NOT NULL
),

grp AS (
  SELECT
    CASE
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%died%' OR LOWER(discharge_location) LIKE '%death%' OR
           LOWER(discharge_location) LIKE 'died in hospital%' OR LOWER(discharge_location) LIKE '%died in hospital%' THEN 'In-hospital death'
      ELSE NULL
    END AS discharge_group,
    LOS_days
  FROM base
  WHERE
    CASE
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%died%' OR LOWER(discharge_location) LIKE '%death%' OR
           LOWER(discharge_location) LIKE 'died in hospital%' OR LOWER(discharge_location) LIKE '%died in hospital%' THEN 'In-hospital death'
      ELSE NULL
    END IS NOT NULL
),

stats AS (
  SELECT
    discharge_group,
    COUNT(*) AS n,
    AVG(LOS_days) AS los_mean_days,
    APPROX_QUANTILES(LOS_days, 100) AS quantiles_100,
    SUM(CASE WHEN LOS_days <= 10 THEN 1 ELSE 0 END) AS cnt_le_10
  FROM grp
  GROUP BY discharge_group
)

SELECT
  discharge_group AS discharge_bucket,
  n,
  los_mean_days,
  quantiles_100[OFFSET(24)] AS p25,  -- 25th percentile
  quantiles_100[OFFSET(49)] AS p50,  -- 50th percentile
  quantiles_100[OFFSET(74)] AS p75,  -- 75th percentile
  quantiles_100[OFFSET(89)] AS p90,  -- 90th percentile
  SAFE_DIVIDE(cnt_le_10, n) * 100 AS percent_le_10_days
FROM stats
ORDER BY discharge_group;