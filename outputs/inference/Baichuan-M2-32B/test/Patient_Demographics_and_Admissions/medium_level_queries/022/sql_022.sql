WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Compute LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Determine discharge category
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'home'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'hospice'
      ELSE 'other' -- Will be filtered out
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admission_type = 'transfer from another hospital'
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_category,
  -- Calculate mean LOS
  AVG(los_days) AS mean_los,
  -- Calculate percentiles using PERCENTILE_CONT with corrected syntax
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_days) AS p25_los,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY los_days) AS p50_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS p75_los,
  PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY los_days) AS p90_los,
  -- Calculate percentage of admissions with LOS <= 10 days
  (SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS pct_le_10_days
FROM
  eligible_admissions
WHERE
  discharge_category IN ('home', 'hospice', 'in-hospital death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;