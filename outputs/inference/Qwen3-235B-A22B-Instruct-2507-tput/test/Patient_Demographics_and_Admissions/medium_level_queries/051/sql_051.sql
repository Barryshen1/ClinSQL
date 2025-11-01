WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.gender,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_location,
    -- Compute LOS in days as decimal
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND a.admission_location IS NOT NULL
    AND UPPER(a.admission_location) LIKE '%EMERGENCY%'
),
filtered_cohort AS (
  SELECT *
  FROM patient_admissions
  WHERE age_at_admission BETWEEN 68 AND 78
),
summary_stats AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Died'
      ELSE 'Discharged Alive'
    END AS discharge_status,
    AVG(los_days) AS mean_los,
    STDDEV(los_days) AS sd_los,
    AVG(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0.0 END) AS pct_los_le_7
  FROM filtered_cohort
  GROUP BY discharge_status
)
SELECT
  discharge_status,
  ROUND(mean_los, 2) AS mean_los_days,
  ROUND(sd_los, 2) AS sd_los_days,
  ROUND(pct_los_le_7 * 100, 1) AS pct_los_le_7_days
FROM summary_stats
ORDER BY discharge_status;