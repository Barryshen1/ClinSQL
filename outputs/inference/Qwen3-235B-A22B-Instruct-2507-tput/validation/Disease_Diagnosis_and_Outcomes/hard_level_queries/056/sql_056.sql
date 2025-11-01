WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),

-- Get diagnosis counts per admission
diagnosis_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  GROUP BY hadm_id
),

-- Identify septic shock admissions (using ICD-10 codes R65.20, R65.21)
septic_shock_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code IN ('R6520', 'R6521')  -- Note: MIMIC stores ICD-10 without dots
),

-- ICU admission flag
icu_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
)

-- Final cohort: male, 63-73, septic shock, >15 diagnoses
SELECT
  AVG(dc.diagnosis_count) AS mean_risk_score,  -- using diagnosis count as proxy
  AVG(CASE 
        WHEN pa.dod IS NOT NULL AND DATETIME_DIFF(pa.dod, pa.admittime, DAY) <= 90 
        THEN 1.0 ELSE 0.0 END) AS mortality_90day_rate,
  AVG(CASE WHEN iu.hadm_id IS NOT NULL THEN 1.0 ELSE 0.0 END) AS major_complication_rate,
  AVG(CASE 
        WHEN pa.hospital_expire_flag = 0 
        THEN DATETIME_DIFF(pa.dischtime, pa.admittime, HOUR) / 24.0 
        ELSE NULL END) AS survivor_los_days,
  -- Percentile of diagnosis count = 16 in this cohort
  APPROX_QUANTILES(
    CASE WHEN dc.diagnosis_count <= 16 THEN 16 ELSE NULL END, 
    100 IGNORE NULLS
  )[OFFSET(50)] AS diagnosis_count_16_percentile_approx
FROM patient_admissions pa
INNER JOIN diagnosis_counts dc ON pa.hadm_id = dc.hadm_id
INNER JOIN septic_shock_codes ss ON pa.hadm_id = ss.hadm_id
LEFT JOIN icu_admissions iu ON pa.hadm_id = iu.hadm_id
WHERE dc.diagnosis_count > 15
  AND ss.hadm_id IS NOT NULL;