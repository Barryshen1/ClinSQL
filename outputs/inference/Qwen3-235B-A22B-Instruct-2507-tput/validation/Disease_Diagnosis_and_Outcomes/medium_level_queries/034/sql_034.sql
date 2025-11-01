WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Time to death in hours for non-survivors
    DATETIME_DIFF(a.deathtime, a.admittime, HOUR) AS time_to_death_hours
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
),

heart_failure_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
),

cohort AS (
  SELECT
    pa.*
  FROM patient_admissions pa
  INNER JOIN heart_failure_diagnoses hf
    ON pa.hadm_id = hf.hadm_id
),

grouped_stats AS (
  SELECT
    CASE WHEN los_days < 8 THEN '<8 days' ELSE '≥8 days' END AS los_group,
    COUNT(*) AS admission_count,
    SUM(hospital_expire_flag) AS deaths,
    -- Compute median time-to-death in hours using approximate quantiles
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 1 THEN time_to_death_hours END, 1000)[OFFSET(500)] AS median_time_to_death_hours
  FROM cohort
  GROUP BY los_group
)

SELECT
  los_group,
  admission_count AS N_admissions,
  ROUND(100.0 * deaths / admission_count, 2) AS mortality_rate_percent,
  median_time_to_death_hours
FROM grouped_stats
ORDER BY los_group;