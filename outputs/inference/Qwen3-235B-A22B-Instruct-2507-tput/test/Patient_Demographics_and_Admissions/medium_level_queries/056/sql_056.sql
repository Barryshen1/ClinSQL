WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.admission_location IS NOT NULL
    AND UPPER(a.admission_location) LIKE '%EMER%' OR UPPER(a.admission_location) LIKE '%ED%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
),
filtered_cohort AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    los_days
  FROM patient_admissions
  WHERE age_at_admission BETWEEN 67 AND 77
),
summary_stats AS (
  SELECT
    CASE WHEN hospital_expire_flag = 0 THEN 'Alive' ELSE 'Died' END AS discharge_status,
    COUNT(*) AS total,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS count_los_ge7,
    SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS count_los_ge14,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS count_los_le10
  FROM filtered_cohort
  GROUP BY hospital_expire_flag
)
SELECT
  discharge_status,
  ROUND(SAFE_DIVIDE(count_los_ge7, total), 3) AS prop_los_ge7,
  ROUND(SAFE_DIVIDE(count_los_ge14, total), 3) AS prop_los_ge14,
  ROUND(SAFE_DIVIDE(count_los_le10, total), 3) AS percentile_rank_10day_los
FROM summary_stats
ORDER BY discharge_status;