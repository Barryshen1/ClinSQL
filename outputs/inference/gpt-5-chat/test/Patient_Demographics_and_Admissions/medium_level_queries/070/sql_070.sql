WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los,
    -- Outcome category
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Discharged home'
      ELSE 'Other'
    END AS disposition
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.edregtime IS NOT NULL
)
SELECT
  disposition,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND( (APPROX_QUANTILES(los, 100)[OFFSET(50)]), 2 ) AS median_los_days,
  ROUND( (APPROX_QUANTILES(los, 100)[OFFSET(75)]), 2 ) AS p75_los_days,
  ROUND( (APPROX_QUANTILES(los, 100)[OFFSET(90)]), 2 ) AS p90_los_days,
  ROUND(AVG(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100, 1) AS percentile_rank_10d
FROM cohort
WHERE disposition IN ('Discharged home', 'Hospice', 'In-hospital death')
GROUP BY disposition
ORDER BY disposition;