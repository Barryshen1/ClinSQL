WITH patients_female_age AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 68 AND 78
),
admissions_base AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_female_age pfa ON a.subject_id = pfa.subject_id
),
ami_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = 1
    AND (icd_code LIKE '410%' OR icd_code LIKE 'I21%')
),
icu_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
drg_data AS (
  SELECT subject_id, hadm_id, 
         ANY_VALUE(drg_mortality) AS risk_score,
         ANY_VALUE(drg_severity) AS drg_severity  -- Proxy if needed; assume 1 per hadm
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  WHERE drg_type = 'MS-DRG'
  GROUP BY subject_id, hadm_id  -- Handle multiples; one row per hadm
),
ami_icu_cohort AS (
  SELECT ab.*, dd.risk_score, p.dod,
         CASE WHEN p.dod IS NOT NULL 
                   AND p.dod >= DATE(ab.admittime) 
                   AND p.dod <= DATE(TIMESTAMP_ADD(ab.admittime, INTERVAL 90 DAY)) 
              THEN 1 ELSE 0 END AS mort90_flag,
         CASE WHEN ab.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS complication_flag  -- In-hospital death as proxy
  FROM admissions_base ab
  INNER JOIN ami_hadm ah ON ab.hadm_id = ah.hadm_id
  INNER JOIN icu_hadm ih ON ab.hadm_id = ih.hadm_id
  INNER JOIN drg_data dd ON ab.hadm_id = dd.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ab.subject_id = p.subject_id
),
general_cohort AS (
  SELECT ab.*, dd.risk_score,
         CASE WHEN ab.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS complication_flag
  FROM admissions_base ab
  INNER JOIN drg_data dd ON ab.hadm_id = dd.hadm_id  -- All age/gender inpatients with DRG
),
cohort_stats AS (
  SELECT
    'AMI_ICU_Cohort' AS cohort_type,
    APPROX_QUANTILES(risk_score, 100)[SAFE_OFFSET(50)] AS median_risk_score,
    APPROX_QUANTILES(risk_score, 100)[SAFE_OFFSET(25)] AS iqr_low,
    APPROX_QUANTILES(risk_score, 100)[SAFE_OFFSET(75)] AS iqr_high,
    AVG(mort90_flag) AS mortality_90d_rate,
    AVG(complication_flag) AS major_complication_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days END, 100)[SAFE_OFFSET(50)] AS median_los_survivors
  FROM ami_icu_cohort
  UNION ALL
  SELECT
    'General_Inpatients' AS cohort_type,
    APPROX_QUANTILES(risk_score, 100)[SAFE_OFFSET(50)] AS median_risk_score,
    APPROX_QUANTILES(risk_score, 100)[SAFE_OFFSET(25)] AS iqr_low,
    APPROX_QUANTILES(risk_score, 100)[SAFE_OFFSET(75)] AS iqr_high,
    NULL AS mortality_90d_rate,  -- Not requested for general
    AVG(complication_flag) AS major_complication_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days END, 100)[SAFE_OFFSET(50)] AS median_los_survivors
  FROM general_cohort
)
SELECT
  cs.*,
  -- Risk percentile: cohort median's rank in general (patient proxy)
  (SELECT COUNTIF(gc.risk_score <= cs.median_risk_score) * 100.0 / NULLIF(COUNT(*), 0)
   FROM general_cohort gc) AS patient_risk_percentile_general
FROM cohort_stats cs;