WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.hospital_expire_flag,
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND LOWER(a.admission_location) LIKE '%emergency%'
    AND a.dischtime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 41 AND 51
),
stratified_stats AS (
  SELECT
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    COUNTIF(los_days <= 5) * 100.0 / COUNT(*) AS pct_los_le_5_days
  FROM patient_admissions
  GROUP BY hospital_expire_flag
)
SELECT
  hospital_expire_flag,
  mean_los,
  median_los,
  pct_los_le_5_days
FROM stratified_stats
ORDER BY hospital_expire_flag;