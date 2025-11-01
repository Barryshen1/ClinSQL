WITH 
  -- Calculate comorbidity burden percentile
  comorbidity_burden AS (
    SELECT 
      subject_id, 
      hadm_id, 
      drg_severity, 
      drg_mortality,
      PERCENT_RANK() OVER (PARTITION BY subject_id ORDER BY drg_severity) AS comorbidity_percentile
    FROM 
      `physionet-data.mimiciv_3_1_hosp.drgcodes`
  ),

  -- Identify patients with DVT
  dvt_patients AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code LIKE '453%'
  ),

  -- Filter patients by age, gender, and comorbidity burden
  cohort_patients AS (
    SELECT 
      p.subject_id, 
      p.anchor_age, 
      p.gender, 
      a.hadm_id, 
      a.admittime, 
      a.hospital_expire_flag,
      a.deathtime,
      cb.comorbidity_percentile
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN 
      comorbidity_burden cb ON a.subject_id = cb.subject_id AND a.hadm_id = cb.hadm_id
    JOIN 
      dvt_patients dp ON p.subject_id = dp.subject_id AND a.hadm_id = dp.hadm_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 59 AND 69
      AND cb.comorbidity_percentile >= 0.75
  ),

  -- Calculate 30-day mortality
  thirty_day_mortality AS (
    SELECT 
      COUNT(CASE WHEN hospital_expire_flag = 1 OR (deathtime IS NOT NULL AND DATE_DIFF(CAST(deathtime AS DATE), CAST(admittime AS DATE)) <= 30) THEN 1 END) AS deaths,
      COUNT(*) AS total_patients
    FROM 
      cohort_patients
  ),

  -- Calculate median survival for decedents
  survival_time AS (
    SELECT 
      subject_id, 
      hadm_id, 
      DATE_DIFF(CAST(COALESCE(deathtime, TIMESTAMP_ADD(CAST(admittime AS TIMESTAMP), INTERVAL 30 DAY)) AS DATE), CAST(admittime AS DATE)) AS survival_days
    FROM 
      cohort_patients
    WHERE 
      hospital_expire_flag = 1 OR deathtime IS NOT NULL
  )

-- Final query
SELECT 
  COUNT(*) AS cohort_size,
  (SELECT deaths / total_patients FROM thirty_day_mortality) AS thirty_day_mortality_rate,
  -- Assuming major complication rate requires additional tables/columns not provided
  -- This is a placeholder and may need adjustment
  0 AS major_complication_rate,
  APPROX_QUANTILES(survival_days, 4)[OFFSET(2)] AS median_survival_time
FROM 
  cohort_patients
  LEFT JOIN survival_time st ON cohort_patients.subject_id = st.subject_id AND cohort_patients.hadm_id = st.hadm_id;