WITH med_adm AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COALESCE(LOWER(a.discharge_location), '') AS discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND LOWER(s.curr_service) LIKE '%med%'
    )
)

SELECT
  discharge_category,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS p25_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS p50_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
  SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS count_le_10_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_le_10_days
FROM (
  SELECT *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%home%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM med_adm
)
GROUP BY discharge_category
ORDER BY discharge_category;