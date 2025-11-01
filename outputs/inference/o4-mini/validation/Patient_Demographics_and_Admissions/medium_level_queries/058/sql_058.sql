WITH base AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN LOWER(adm.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(adm.discharge_location) LIKE '%snf%'
        OR LOWER(adm.discharge_location) LIKE '%rehab%'
        OR LOWER(adm.discharge_location) LIKE '%ltach%' THEN 'SNF/Rehab/LTACH'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND LOWER(adm.admission_location) LIKE 'transfer%'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND (
      adm.hospital_expire_flag = 1
      OR LOWER(adm.discharge_location) LIKE '%home%'
      OR LOWER(adm.discharge_location) LIKE '%snf%'
      OR LOWER(adm.discharge_location) LIKE '%rehab%'
      OR LOWER(adm.discharge_location) LIKE '%ltach%'
    )
),
quantile_data AS (
  SELECT
    discharge_category,
    APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM base
  GROUP BY discharge_category
)
SELECT
  b.discharge_category,
  COUNT(*)                                             AS n,
  ROUND(AVG(b.los_days), 2)                            AS mean_los_days,
  q.quantiles[OFFSET(25)]                              AS p25,
  q.quantiles[OFFSET(50)]                              AS median,
  q.quantiles[OFFSET(75)]                              AS p75,
  q.quantiles[OFFSET(90)]                              AS p90,
  q.quantiles[OFFSET(95)]                              AS p95,
  ROUND(100 * COUNTIF(b.los_days <= 5) / COUNT(*), 2)   AS percentile_rank_5d
FROM
  base AS b
  JOIN quantile_data AS q
    USING (discharge_category)
GROUP BY
  b.discharge_category,
  q.quantiles
ORDER BY
  b.discharge_category;