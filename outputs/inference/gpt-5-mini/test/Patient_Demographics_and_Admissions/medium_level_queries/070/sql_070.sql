WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- LOS in days, as a floating-point number (fractional days)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    a.hospital_expire_flag,
    COALESCE(a.discharge_location, '') AS discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    -- require complete times and a positive LOS
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
    -- identify ED admissions (primary: edregtime populated; also capture common emergency labels)
    AND (
      a.edregtime IS NOT NULL
      OR LOWER(a.admission_type) = 'emergency'
      OR LOWER(COALESCE(a.admission_location, '')) LIKE '%emerg%'
    )
    -- restrict to admissions that end in one of the three outcomes of interest
    AND (
      a.hospital_expire_flag = 1
      OR LOWER(COALESCE(a.discharge_location, '')) LIKE '%hospice%'
      OR LOWER(COALESCE(a.discharge_location, '')) LIKE '%home%'
    )
),

labeled AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Discharged home'
      ELSE 'Other'
    END AS outcome
  FROM cohort
)

SELECT
  outcome,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- approximate quantiles (APPROX_QUANTILES returns an array of 101 values for 0..100)
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
  -- empirical percentile rank of 10 days (percentage of admissions with LOS <= 10 days)
  ROUND(100.0 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_rank_of_10_days
FROM
  labeled
WHERE
  outcome IN ('Discharged home', 'Hospice', 'In-hospital death')
GROUP BY
  outcome
ORDER BY
  CASE outcome
    WHEN 'Discharged home' THEN 1
    WHEN 'Hospice' THEN 2
    WHEN 'In-hospital death' THEN 3
    ELSE 4
  END;