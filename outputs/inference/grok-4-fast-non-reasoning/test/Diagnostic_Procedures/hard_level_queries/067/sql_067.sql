WITH first_icu_stays AS (
  -- Get first ICU stay per patient
  SELECT subject_id, hadm_id, stay_id, intime, outtime, los,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE subject_id IN (
    -- Male patients 70-80 with ICU stay
    SELECT DISTINCT p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 70 AND 80
  )
  QUALIFY rn = 1
),

hf_cohort AS (
  -- Heart failure cohort: male 70-80 with HF diagnosis
  SELECT 
    f.subject_id, f.hadm_id, f.stay_id, f.intime, f.outtime, f.los,
    a.hospital_expire_flag,
    1 AS has_heart_failure
  FROM first_icu_stays f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON f.hadm_id = d.hadm_id 
    AND d.icd_version = 10  -- Fixed: numeric comparison for ICD-10
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag 
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE LOWER(diag.long_title) LIKE '%heart failure%'
),

general_cohort AS (
  -- General cohort: male 70-80 ICU patients (excluding HF for clean comparison)
  SELECT 
    f.subject_id, f.hadm_id, f.stay_id, f.intime, f.outtime, f.los,
    a.hospital_expire_flag,
    0 AS has_heart_failure
  FROM first_icu_stays f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.hadm_id = a.hadm_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag 
      ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
    WHERE d.icd_version = 10 AND LOWER(diag.long_title) LIKE '%heart failure%'
  ) hf ON f.hadm_id = hf.hadm_id
  WHERE hf.hadm_id IS NULL  -- Exclude HF admissions
),

patient_cohorts AS (
  -- Union HF and general cohorts
  SELECT * FROM hf_cohort
  UNION ALL
  SELECT * FROM general_cohort
),

diagnostic_intensity AS (
  -- Count distinct diagnostic itemids in first 72h per stay
  SELECT 
    c.stay_id,
    COUNT(DISTINCT c.itemid) AS diag_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN first_icu_stays f ON c.stay_id = f.stay_id
  WHERE c.charttime >= f.intime 
    AND c.charttime < TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
    AND c.valuenum IS NOT NULL  -- Proxy for actual measurements
    AND c.itemid NOT IN (220045, 220179)  -- Exclude common non-diagnostic (e.g., GCS components if needed; optional)
  GROUP BY c.stay_id
),

cohort_summary AS (
  SELECT 
    CASE WHEN pc.has_heart_failure = 1 THEN 'Heart Failure' ELSE 'General ICU' END AS cohort,
    COUNT(DISTINCT pc.stay_id) AS n_patients,
    AVG(COALESCE(di.diag_count, 0)) AS mean_diagnostic_intensity,
    PERCENTILE_CONT(COALESCE(di.diag_count, 0), 0.5) OVER (PARTITION BY pc.has_heart_failure) AS median_diagnostic_intensity,
    PERCENTILE_CONT(COALESCE(di.diag_count, 0), 0.75) OVER (PARTITION BY pc.has_heart_failure) AS p75_diagnostic_intensity,
    PERCENTILE_CONT(COALESCE(di.diag_count, 0), 0.95) OVER (PARTITION BY pc.has_heart_failure) AS p95_diagnostic_intensity,
    AVG(pc.los) AS mean_icu_los,
    AVG(pc.hospital_expire_flag) AS hospital_mortality_rate
  FROM patient_cohorts pc
  LEFT JOIN diagnostic_intensity di ON pc.stay_id = di.stay_id
  GROUP BY pc.has_heart_failure
)

SELECT 
  cohort,
  n_patients,
  ROUND(mean_diagnostic_intensity, 2) AS mean_intensity,
  ROUND(median_diagnostic_intensity, 2) AS median_intensity,
  ROUND(p75_diagnostic_intensity, 2) AS p75_intensity,
  ROUND(p95_diagnostic_intensity, 2) AS p95_intensity,
  ROUND(mean_icu_los, 2) AS mean_los_days,
  ROUND(hospital_mortality_rate * 100, 2) AS mortality_pct
FROM cohort_summary
ORDER BY CASE WHEN cohort = 'Heart Failure' THEN 1 ELSE 2 END;