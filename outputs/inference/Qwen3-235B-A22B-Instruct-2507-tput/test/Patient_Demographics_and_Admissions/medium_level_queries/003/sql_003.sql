WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    (DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 3600.0)) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
filtered_admissions AS (
  SELECT *
  FROM patient_admissions
  WHERE age_at_admit >= 80
    AND age_at_admit <= 90
    AND admission_type != 'EMERGENCY'
),
discharge_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'home'
      ELSE NULL
    END AS discharge_group
  FROM filtered_admissions
  WHERE hospital_expire_flag = 1
     OR LOWER(discharge_location) LIKE '%hospice%'
     OR LOWER(discharge_location) LIKE '%home%'
)
SELECT
  discharge_group,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  (SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percent_los_le_14_days
FROM discharge_groups
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY discharge_group;