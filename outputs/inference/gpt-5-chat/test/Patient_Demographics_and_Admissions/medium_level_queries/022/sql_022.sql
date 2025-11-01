WITH target_pop AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.discharge_location,
    SAFE_CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS FLOAT64) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(a.admission_location) LIKE '%hospital%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 0
),
categorized AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_category
  FROM target_pop
)
SELECT
  discharge_category,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days),2) AS mean_los,
  -- Approximate quantiles returns array from min to max — 100 quantiles
  ROUND(ARRAY_AGG(los_days ORDER BY los_days LIMIT 1)[OFFSET(0)],2) AS min_los,
  ROUND( (APPROX_QUANTILES(los_days, 100))[OFFSET(25)], 2) AS p25_los,
  ROUND( (APPROX_QUANTILES(los_days, 100))[OFFSET(50)], 2) AS p50_los,
  ROUND( (APPROX_QUANTILES(los_days, 100))[OFFSET(75)], 2) AS p75_los,
  ROUND( (APPROX_QUANTILES(los_days, 100))[OFFSET(90)], 2) AS p90_los,
  ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_los_le_10
FROM
  categorized
WHERE
  discharge_category IN ('Home','Hospice','In-hospital death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;