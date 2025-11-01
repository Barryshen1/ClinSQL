WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_adm,
    -- Calculate LOS in fractional days
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    -- Categorize discharge destination
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location IN ('HOSPICE', 'HOSPICE HOME') THEN 'hospice'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_type = 'ELECTIVE'  -- Non-emergent
    -- Filter age 89-99 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  -- Include only target discharge categories
  WHERE discharge_category IN ('home', 'hospice', 'in-hospital death')
)
SELECT
  discharge_category,
  COUNT(*) AS num_admissions,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  -- Calculate % with LOS < 5 days
  100.0 * SUM(CASE WHEN los_days < 5 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_under_5_days
FROM filtered_cohort
GROUP BY discharge_category
ORDER BY discharge_category;