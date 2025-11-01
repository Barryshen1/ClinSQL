WITH patients_filtered AS (
  SELECT p.subject_id, p.anchor_age, p.gender, p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
),
-- Get admissions with first admission per patient
admissions_first AS (
  SELECT 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
),
admissions_first_only AS (
  SELECT * EXCEPT(rn)
  FROM admissions_first
  WHERE rn = 1
),
-- Heart failure diagnosis codes (ICD-9: 428, ICD-10: I50)
hf_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
hf_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM admissions_first_only a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN hf_codes hfc ON di.icd_code = hfc.icd_code
),
non_hf_patients AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM admissions_first_only a
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    INNER JOIN hf_codes hfc ON di.icd_code = hfc.icd_code
    WHERE di.hadm_id = a.hadm_id
  )
),
-- Lab events in first 48h
lab_48h AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.flag
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN admissions_first_only a
    ON le.hadm_id = a.hadm_id
  WHERE le.charttime >= a.admittime
    AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
    AND le.flag IS NOT NULL
),
-- Abnormal lab count per patient (HF cohort)
hf_abnormal_labs AS (
  SELECT 
    h.subject_id,
    h.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM hf_patients h
  INNER JOIN lab_48h l ON h.hadm_id = l.hadm_id
  WHERE l.flag NOT IN ('normal') -- Include only abnormal, high, low, critical
  GROUP BY h.subject_id, h.hadm_id
),
-- 95th percentile of abnormal lab count in HF cohort
threshold_95 AS (
  SELECT APPROX_QUANTILES(abnormal_lab_count, 100)[OFFSET(95)] AS threshold
  FROM hf_abnormal_labs
),
-- High instability HF patients (>= 95th percentile)
high_instability_hf AS (
  SELECT hfl.*, h.hospital_expire_flag, h.admittime, h.dischtime
  FROM hf_abnormal_labs hfl
  INNER JOIN hf_patients h ON hfl.hadm_id = h.hadm_id
  CROSS JOIN threshold_95
  WHERE hfl.abnormal_lab_count >= threshold
),
-- Control group: non-HF, same age/gender, first admission
control_abnormal_labs AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM non_hf_patients c
  INNER JOIN lab_48h l ON c.hadm_id = l.hadm_id
  WHERE l.flag NOT IN ('normal')
  GROUP BY c.subject_id, c.hadm_id
),
-- Critical lab rates: flag indicating critical
critical_labs_hf AS (
  SELECT 
    hfl.subject_id,
    COUNT(*) AS total_labs,
    COUNTIF(l.flag LIKE '%critical%') AS critical_labs
  FROM high_instability_hf hfl
  INNER JOIN lab_48h l ON hfl.hadm_id = l.hadm_id
  GROUP BY hfl.subject_id
),
critical_labs_control AS (
  SELECT 
    c.subject_id,
    COUNT(*) AS total_labs,
    COUNTIF(l.flag LIKE '%critical%') AS critical_labs
  FROM control_abnormal_labs c
  INNER JOIN lab_48h l ON c.hadm_id = l.hadm_id
  GROUP BY c.subject_id
),
-- Final summary for high-instability HF patients
summary_hf_high AS (
  SELECT
    COUNT(*) AS patient_count,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / (24*3600.0)) AS mean_los_days
  FROM high_instability_hf
),
-- Critical lab rate comparison
summary_critical_rates AS (
  SELECT
    'HF_high_instability' AS group_name,
    AVG(IFNULL(cl.critical_labs, 0) / IFNULL(cl.total_labs, 1)) AS avg_critical_lab_rate
  FROM critical_labs_hf cl
  UNION ALL
  SELECT
    'Control' AS group_name,
    AVG(IFNULL(clc.critical_labs, 0) / IFNULL(clc.total_labs, 1)) AS avg_critical_lab_rate
  FROM critical_labs_control clc
),
-- Pivot critical lab rates to columns
pivoted_critical_rates AS (
  SELECT
    MAX(CASE WHEN group_name = 'HF_high_instability' THEN avg_critical_lab_rate END) AS hf_critical_rate,
    MAX(CASE WHEN group_name = 'Control' THEN avg_critical_lab_rate END) AS control_critical_rate
  FROM summary_critical_rates
)
-- Final output
SELECT
  (SELECT threshold FROM threshold_95) AS lab_instability_95th_percentile,
  s.mortality_rate AS in_hospital_mortality,
  s.mean_los_days AS mean_los_days,
  p.hf_critical_rate,
  p.control_critical_rate
FROM summary_hf_high s
CROSS JOIN pivoted_critical_rates p;