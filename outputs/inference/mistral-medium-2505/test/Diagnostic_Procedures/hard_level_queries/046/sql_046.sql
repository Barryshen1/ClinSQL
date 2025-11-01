WITH
-- Get ARDS ICD codes
ards_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute respiratory distress syndrome%'
     OR LOWER(long_title) LIKE '%ards%'
     OR icd_code IN ('518.82', '518.84', 'J80', 'J82')
),

-- Get first ICU stay per patient
first_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime AS first_icu_intime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS icu_stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Get patients with ARDS in first ICU stay
ards_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    f.stay_id,
    f.first_icu_intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN first_icu_stays f ON p.subject_id = f.subject_id AND f.icu_stay_rank = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN ards_icd_codes ards ON d.icd_code = ards.icd_code
  WHERE p.gender = 'F'
    AND (p.anchor_age BETWEEN 37 AND 47 OR
         (p.anchor_age - (EXTRACT(YEAR FROM CURRENT_DATE()) - p.anchor_year)) BETWEEN 37 AND 47)
),

-- Get all ICU patients (for comparison)
all_icu_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    f.stay_id,
    f.first_icu_intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN first_icu_stays f ON p.subject_id = f.subject_id AND f.icu_stay_rank = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
),

-- Get procedures in first 72 hours of ICU stay
procedures_72h AS (
  SELECT
    p.subject_id,
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN first_icu_stays f ON p.subject_id = f.subject_id AND p.stay_id = f.stay_id
  WHERE p.starttime BETWEEN f.first_icu_intime AND TIMESTAMP_ADD(f.first_icu_intime, INTERVAL 72 HOUR)
  GROUP BY p.subject_id, p.stay_id
),

-- Combine with patient data
ards_with_procedures AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    COALESCE(p.procedure_count, 0) AS procedure_count,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS hospital_los_days,
    a.hospital_expire_flag
  FROM ards_patients a
  LEFT JOIN procedures_72h p ON a.subject_id = p.subject_id AND a.stay_id = p.stay_id
),

all_icu_with_procedures AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    COALESCE(p.procedure_count, 0) AS procedure_count,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS hospital_los_days,
    a.hospital_expire_flag
  FROM all_icu_patients a
  LEFT JOIN procedures_72h p ON a.subject_id = p.subject_id AND a.stay_id = p.stay_id
)

-- Final results
SELECT
  'ARDS Patients (Female 37-47)' AS cohort,
  COUNT(*) AS patient_count,
  PERCENTILE_CONT(procedure_count, 0.75) OVER() AS p75_procedures,
  PERCENTILE_CONT(procedure_count, 0.90) OVER() AS p90_procedures,
  AVG(hospital_los_days) AS mean_hospital_los,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM ards_with_procedures

UNION ALL

SELECT
  'All ICU Patients' AS cohort,
  COUNT(*) AS patient_count,
  PERCENTILE_CONT(procedure_count, 0.75) OVER() AS p75_procedures,
  PERCENTILE_CONT(procedure_count, 0.90) OVER() AS p90_procedures,
  AVG(hospital_los_days) AS mean_hospital_los,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM all_icu_with_procedures;