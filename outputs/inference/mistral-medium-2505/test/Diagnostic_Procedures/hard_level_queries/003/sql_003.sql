WITH
-- Get ARDS ICD codes (J80, J82, etc.)
ards_icd_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('J80', 'J82')  -- ARDS ICD-10 codes
),

-- Get female patients aged 84-94 with ARDS in ICU
female_ards_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN ards_icd_codes ards ON d.icd_code = ards.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND p.anchor_age IS NOT NULL
),

-- Get all ICU patients for comparison
all_icu_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
),

-- Count distinct procedures in first 24 hours of ICU for ARDS patients
ards_procedure_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM female_ards_patients f
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
  WHERE
    TIMESTAMP_DIFF(p.chartdate, f.icu_intime, HOUR) BETWEEN 0 AND 24
  GROUP BY f.subject_id, f.hadm_id, f.stay_id
),

-- Count distinct procedures in first 24 hours of ICU for all patients
all_procedure_counts AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM all_icu_patients a
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id
  WHERE
    TIMESTAMP_DIFF(p.chartdate, a.icu_intime, HOUR) BETWEEN 0 AND 24
  GROUP BY a.subject_id, a.hadm_id, a.stay_id
),

-- Combine ARDS patients with their procedure counts
ards_with_counts AS (
  SELECT
    f.*,
    COALESCE(p.procedure_count, 0) AS procedure_count
  FROM female_ards_patients f
  LEFT JOIN ards_procedure_counts p ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id AND f.stay_id = p.stay_id
),

-- Combine all patients with their procedure counts
all_with_counts AS (
  SELECT
    a.*,
    COALESCE(p.procedure_count, 0) AS procedure_count
  FROM all_icu_patients a
  LEFT JOIN all_procedure_counts p ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id AND a.stay_id = p.stay_id
),

-- Calculate percentiles for ARDS patients
ards_stats AS (
  SELECT
    PERCENTILE_CONT(procedure_count, 0.25) AS percentile_25,
    PERCENTILE_CONT(procedure_count, 0.75) AS percentile_75,
    PERCENTILE_CONT(procedure_count, 0.95) AS percentile_95,
    AVG(hospital_los_hours/24) AS avg_hospital_los_days,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hospital_mortality_rate
  FROM ards_with_counts
),

-- Calculate percentiles for all ICU patients
all_stats AS (
  SELECT
    PERCENTILE_CONT(procedure_count, 0.25) AS percentile_25,
    PERCENTILE_CONT(procedure_count, 0.75) AS percentile_75,
    PERCENTILE_CONT(procedure_count, 0.95) AS percentile_95,
    AVG(hospital_los_hours/24) AS avg_hospital_los_days,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hospital_mortality_rate
  FROM all_with_counts
)

-- Final results
SELECT
  'Female 84-94 with ARDS' AS patient_group,
  percentile_25,
  percentile_75,
  percentile_95,
  avg_hospital_los_days,
  hospital_mortality_rate
FROM ards_stats

UNION ALL

SELECT
  'All ICU patients' AS patient_group,
  percentile_25,
  percentile_75,
  percentile_95,
  avg_hospital_los_days,
  hospital_mortality_rate
FROM all_stats;