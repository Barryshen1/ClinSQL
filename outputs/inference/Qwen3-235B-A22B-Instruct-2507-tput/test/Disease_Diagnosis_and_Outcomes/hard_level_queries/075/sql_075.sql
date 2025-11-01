WITH patients_filtered AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 44 AND 54
),
admissions_with_los AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
),
diagnoses AS (
  SELECT 
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.icd_version = 10
    AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%')
),
ich_cohort AS (
  SELECT DISTINCT a.*
  FROM admissions_with_los a
  INNER JOIN diagnoses d ON a.hadm_id = d.hadm_id
),
non_ich_cohort AS (
  SELECT a.*
  FROM admissions_with_los a
  WHERE NOT EXISTS (
    SELECT 1 FROM diagnoses d WHERE d.hadm_id = a.hadm_id
  )
),
drg_scores AS (
  SELECT 
    hadm_id,
    drg_severity
  FROM `physionet-data.mimiciv_3_1_hosp`.drgcodes
  WHERE drg_type = 'std'
),
ich_with_severity AS (
  SELECT 
    i.*,
    d.drg_severity
  FROM ich_cohort i
  LEFT JOIN drg_scores d ON i.hadm_id = d.hadm_id
),
non_ich_with_severity AS (
  SELECT 
    n.*,
    d.drg_severity
  FROM non_ich_cohort n
  LEFT JOIN drg_scores d ON n.hadm_id = d.hadm_id
),
ich_stats AS (
  SELECT
    APPROX_QUANTILES(drg_severity, 1000)[OFFSET(500)] AS ich_median_risk,
    APPROX_QUANTILES(drg_severity, 1000)[OFFSET(250)] AS ich_iqr_lower,
    APPROX_QUANTILES(drg_severity, 1000)[OFFSET(750)] AS ich_iqr_upper,
    COUNT(CASE 
      WHEN deathtime IS NOT NULL 
       AND DATETIME_DIFF(deathtime, admittime, DAY) <= 90 
      THEN 1 END) * 1.0 / COUNT(*) AS ich_mortality_90d_rate,
    COUNT(CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu`.icustays icu 
      WHERE icu.hadm_id = i.hadm_id
    ) THEN 1 END) * 1.0 / COUNT(*) AS ich_complication_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days END, 1000)[OFFSET(500)] AS ich_median_survivor_los
  FROM ich_with_severity i
  WHERE drg_severity IS NOT NULL
),
non_ich_stats AS (
  SELECT
    APPROX_QUANTILES(drg_severity, 1000)[OFFSET(500)] AS non_ich_median_risk,
    APPROX_QUANTILES(drg_severity, 1000)[OFFSET(250)] AS non_ich_iqr_lower,
    APPROX_QUANTILES(drg_severity, 1000)[OFFSET(750)] AS non_ich_iqr_upper,
    COUNT(CASE 
      WHEN deathtime IS NOT NULL 
       AND DATETIME_DIFF(deathtime, admittime, DAY) <= 90 
      THEN 1 END) * 1.0 / COUNT(*) AS non_ich_mortality_90d_rate,
    COUNT(CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu`.icustays icu 
      WHERE icu.hadm_id = n.hadm_id
    ) THEN 1 END) * 1.0 / COUNT(*) AS non_ich_complication_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days END, 1000)[OFFSET(500)] AS non_ich_median_survivor_los,
    ARRAY_AGG(drg_severity ORDER BY drg_severity) AS control_severities
  FROM non_ich_with_severity n
  WHERE drg_severity IS NOT NULL
),
matched_percentile AS (
  SELECT
    AVG(
      (SELECT 
         SUM(CASE WHEN s <= i.drg_severity THEN 1 ELSE 0 END) * 1.0 / COUNT(*) 
       FROM UNNEST(ns.control_severities) s
      )
    ) AS ich_matched_risk_percentile
  FROM ich_with_severity i
  CROSS JOIN non_ich_stats ns
)
SELECT
  ich_median_risk,
  ich_iqr_lower,
  ich_iqr_upper,
  ich_mortality_90d_rate,
  ich_complication_rate,
  ich_median_survivor_los,
  non_ich_median_risk,
  non_ich_iqr_lower,
  non_ich_iqr_upper,
  non_ich_mortality_90d_rate,
  non_ich_complication_rate,
  non_ich_median_survivor_los,
  ich_matched_risk_percentile
FROM ich_stats
CROSS JOIN non_ich_stats
CROSS JOIN matched_percentile;