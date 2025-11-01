WITH admissions_cte AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Calculate LOS in full days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Derive discharge category
    CASE
      WHEN a.hospital_expire_flag = 1
        OR a.discharge_location LIKE '%EXPIRED%'
        OR a.discharge_location LIKE '%DEAD%' THEN 'in-hospital death'
      WHEN a.discharge_location LIKE '%HOME%' THEN 'home'
      WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    -- Transfer‐in from another hospital
    AND a.admission_location LIKE 'TRANSFER%HOSPITAL%'
)
SELECT
  discharge_category,
  ROUND(AVG(los_days), 1)                                    AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)]                AS p25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)]                AS p50_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)]                AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)]                AS p90_los,
  ROUND(100.0 * SUM(IF(los_days <= 10, 1, 0)) / COUNT(*), 1) AS pct_los_le_10_days,
  COUNT(*)                                                   AS n_admissions
FROM
  admissions_cte
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;