WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit,
    -- Compute LOS in days
    DATETIME_DIFF(CAST(a.dischtime AS DATETIME), CAST(a.admittime AS DATETIME), SECOND) / (24*60*60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND a.dischtime IS NOT NULL
),
filtered_cohort AS (
  SELECT
    subject_id,
    hadm_id,
    discharge_location,
    hospital_expire_flag,
    los_days,
    -- Categorize discharge group
    CASE
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB/DAY TREATMENT', 'LONG TERM CARE HOSPITAL') THEN 'snf_rehab_ltach'
      WHEN hospital_expire_flag = 1 THEN 'in_hospital_mortality'
      ELSE NULL
    END AS discharge_group
  FROM patient_admissions
  WHERE age_at_admit BETWEEN 37 AND 47
    AND discharge_location IS NOT NULL
),
grouped_stats AS (
  SELECT
    discharge_group,
    COUNT(*) AS n,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95,
    -- Compute percentile rank of 5-day stay within each group
    SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank_of_5day
  FROM filtered_cohort
  GROUP BY discharge_group
  HAVING COUNT(*) > 0
)
SELECT
  discharge_group,
  n,
  mean_los,
  p25,
  median,
  p75,
  p90,
  p95,
  percentile_rank_of_5day
FROM grouped_stats
ORDER BY
  CASE discharge_group
    WHEN 'home' THEN 1
    WHEN 'snf_rehab_ltach' THEN 2
    WHEN 'in_hospital_mortality' THEN 3
  END;