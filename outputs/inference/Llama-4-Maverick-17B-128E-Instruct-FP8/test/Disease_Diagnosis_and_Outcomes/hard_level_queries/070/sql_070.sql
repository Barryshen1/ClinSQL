WITH 
dvt_diagnoses AS (
  SELECT DISTINCT 
    d.hadm_id, 
    d.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    dicd.long_title LIKE '%deep vein thrombosis%'
),
dvt_patients AS (
  SELECT DISTINCT 
    p.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    a.deathtime, 
    a.admittime, 
    a.dischtime,
    COUNT(DISTINCT d.icd_code) OVER (PARTITION BY a.hadm_id) as comorbidity_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN 
    dvt_diagnoses d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 59 AND 69
),
comorbidity_percentile AS (
  SELECT 
    subject_id, 
    hadm_id, 
    comorbidity_count,
    PERCENT_RANK() OVER (ORDER BY comorbidity_count) as comorbidity_percentile
  FROM 
    dvt_patients
),
cohort AS (
  SELECT 
    dp.subject_id, 
    dp.hadm_id, 
    dp.admittime, 
    dp.deathtime, 
    dp.dischtime,
    dp.comorbidity_count
  FROM 
    dvt_patients dp
  JOIN 
    comorbidity_percentile cp ON dp.hadm_id = cp.hadm_id
  WHERE 
    cp.comorbidity_percentile >= 0.75
),
metrics AS (
  SELECT 
    COUNT(*) as cohort_size,
    AVG(CASE WHEN deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30 THEN 1.0 ELSE 0 END) as thirty_day_mortality,
    AVG(CASE 
      WHEN deathtime IS NOT NULL 
        OR (SELECT MAX(los) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE hadm_id = cohort.hadm_id) > 7 
      THEN 1.0 ELSE 0 END) as major_complication_rate,
    APPROX_QUANTILES(TIMESTAMP_DIFF(deathtime, admittime, DAY), 1000)[OFFSET(500)] as median_survival_decedents,
    APPROX_QUANTILES(comorbidity_count, 1000)[OFFSET(250)] as q1_comorbidity,
    APPROX_QUANTILES(comorbidity_count, 1000)[OFFSET(500)] as q2_comorbidity,
    APPROX_QUANTILES(comorbidity_count, 1000)[OFFSET(750)] as q3_comorbidity
  FROM 
    cohort
  WHERE 
    deathtime IS NOT NULL -- For median survival of decedents
)
SELECT 
  cohort_size,
  thirty_day_mortality,
  major_complication_rate,
  median_survival_decedents,
  q1_comorbidity,
  q2_comorbidity,
  q3_comorbidity
FROM 
  metrics;