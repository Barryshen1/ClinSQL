WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COALESCE(LOWER(a.discharge_location), '') AS discharge_location,
    p.anchor_age,
    p.gender,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 1440.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- capture admissions transferred from another hospital (case-insensitive)
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer%'
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%hosp%'
)

SELECT
  discharge_group,
  n,
  ROUND(q_array[OFFSET(2)], 3) AS median_los_days,
  ROUND(q_array[OFFSET(3)] - q_array[OFFSET(1)], 3) AS iqr_los_days,
  ROUND(100.0 * leq10 / NULLIF(n,0), 1) AS pct_leq_10_days
FROM (
  SELECT
    discharge_group,
    COUNT(*) AS n,
    APPROX_QUANTILES(los_days, 4) AS q_array,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS leq10
  FROM (
    SELECT
      CASE
        WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
        WHEN discharge_location LIKE '%home%' THEN 'home'
        ELSE 'facility'
      END AS discharge_group,
      los_days
    FROM cohort
  )
  GROUP BY discharge_group
)
ORDER BY
  CASE
    WHEN discharge_group = 'home' THEN 1
    WHEN discharge_group = 'facility' THEN 2
    WHEN discharge_group = 'in-hospital death' THEN 3
    ELSE 4
  END;