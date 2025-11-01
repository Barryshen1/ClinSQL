WITH
  base AS (
    SELECT
      CASE
        WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 'In-hospital death'
        WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Hospice'
        WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
        ELSE 'Other'
      END AS discharge_group,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE LOWER(p.gender) = 'male'
      AND p.anchor_age BETWEEN 89 AND 99
      AND LOWER(a.admission_type) = 'elective'
      AND a.dischtime IS NOT NULL
  ),
  filtered AS (
    SELECT discharge_group, los_days
    FROM base
    WHERE discharge_group IN ('Home','Hospice','In-hospital death')
  ),
  stats AS (
    SELECT
      discharge_group,
      COUNT(*) AS n,
      AVG(los_days) AS mean_los,
      SUM(CASE WHEN los_days < 5.0 THEN 1 ELSE 0 END) AS count_less5
    FROM filtered
    GROUP BY discharge_group
  ),
  quantiles AS (
    SELECT
      discharge_group,
      APPROX_QUANTILES(los_days, 100) AS q
    FROM filtered
    GROUP BY discharge_group
  )
SELECT
  s.discharge_group,
  s.mean_los,
  quant.q[OFFSET(50)] AS median_los,
  quant.q[OFFSET(75)] AS p75_los,
  quant.q[OFFSET(90)] AS p90_los,
  SAFE_DIVIDE(s.count_less5, s.n) * 100 AS pct_less5
FROM stats AS s
JOIN quantiles AS quant
  ON quant.discharge_group = s.discharge_group
ORDER BY s.discharge_group;