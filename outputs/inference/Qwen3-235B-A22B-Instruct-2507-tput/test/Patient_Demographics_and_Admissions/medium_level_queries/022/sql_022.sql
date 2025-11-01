WITH patient_los AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Calculate age at admission
    (EXTRACT(YEAR FROM a.admittime) + EXTRACT(MONTH FROM a.admittime) / 12 + EXTRACT(DAY FROM a.admittime) / 365.25)
    - p.anchor_year + p.anchor_age AS age_at_admission,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
),
filtered_cohort AS (
  SELECT *
  FROM patient_los
  WHERE age_at_admission >= 81 AND age_at_admission <= 91
),
discharge_groups AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'home'
      ELSE NULL
    END AS discharge_group,
    los_days
  FROM filtered_cohort
  WHERE discharge_location IS NOT NULL
),
stats AS (
  SELECT
    discharge_group,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_los_le_10
  FROM discharge_groups
  WHERE discharge_group IS NOT NULL
  GROUP BY discharge_group
)
SELECT
  discharge_group,
  ROUND(mean_los, 2) AS mean_los,
  ROUND(p25_los, 2) AS p25_los,
  ROUND(p50_los, 2) AS p50_los,
  ROUND(p75_los, 2) AS p75_los,
  ROUND(p90_los, 2) AS p90_los,
  ROUND(pct_los_le_10, 1) AS pct_los_le_10
FROM stats
ORDER BY discharge_group;