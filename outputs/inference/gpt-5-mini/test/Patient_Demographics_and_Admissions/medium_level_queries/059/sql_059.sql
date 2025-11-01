WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    -- transferred from another hospital: admission_location mentions transfer and hospital
    AND a.admission_location IS NOT NULL
    AND LOWER(a.admission_location) LIKE '%transfer%'
    AND LOWER(a.admission_location) LIKE '%hospital%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.hadm_id IS NOT NULL
),
categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'home'
      ELSE 'other'
    END AS discharge_category
  FROM cohort
)
SELECT
  discharge_category,
  COUNT(*) AS total_stays,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS stays_los_ge_7,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)), 2) AS prop_los_ge_7_percent,
  -- 7-day percentile: proportion of stays with LOS <= 7 days (i.e., percent discharged by 7 days)
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_discharged_by_7_percent
FROM
  categorized
WHERE
  discharge_category IN ('home', 'hospice', 'in-hospital death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;