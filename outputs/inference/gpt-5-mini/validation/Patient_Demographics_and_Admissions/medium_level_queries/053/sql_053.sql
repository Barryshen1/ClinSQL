WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- length of stay in days (fractional)
    SAFE_DIVIDE(CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) AS FLOAT64), 86400.0) AS length_days,
    -- classify discharge category, prioritizing in-hospital death
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(COALESCE(a.discharge_location, '')) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(COALESCE(a.discharge_location, '')) LIKE '%home%' THEN 'home'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_type = 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- ensure non-negative length
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
)
SELECT
  discharge_category,
  cnt AS admission_count,
  qarr[OFFSET(50)] AS median_los_days,
  qarr[OFFSET(25)] AS q1_los_days,
  qarr[OFFSET(75)] AS q3_los_days,
  (qarr[OFFSET(75)] - qarr[OFFSET(25)]) AS iqr_los_days
FROM (
  SELECT
    discharge_category,
    COUNT(*) AS cnt,
    APPROX_QUANTILES(length_days, 100) AS qarr
  FROM cohort
  WHERE discharge_category IN ('home', 'hospice', 'in-hospital death')
  GROUP BY discharge_category
)
ORDER BY
  discharge_category;