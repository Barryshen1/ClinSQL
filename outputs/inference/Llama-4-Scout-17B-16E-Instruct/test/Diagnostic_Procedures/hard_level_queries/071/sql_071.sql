WITH 
-- Identify female patients aged 50-60 with ICH
patients_ich AS (
  SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.hospital_expire_flag, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 50 AND 60
  AND d.icd_code LIKE '907.0%'  -- Intracranial hemorrhage
),

-- ICU stays for these patients
icu_stays AS (
  SELECT i.stay_id, i.subject_id, i.hadm_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_ich p ON i.hadm_id = p.hadm_id
),

-- Procedure burden within 72 hours of ICU admission
procedure_burden AS (
  SELECT 
    icu.hadm_id,
    COUNT(pe.itemid) AS procedure_count
  FROM icu_stays icu
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON icu.stay_id = pe.stay_id
  WHERE pe.starttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY icu.hadm_id
),

-- Calculate percentiles and max for procedure burden
percentiles AS (
  SELECT 
    APPROX_QUANTILES(procedure_count, 4)[OFFSET(0)] AS p25,
    APPROX_QUANTILES(procedure_count, 4)[OFFSET(1)] AS p50,
    APPROX_QUANTILES(procedure_count, 4)[OFFSET(3)] AS p90,
    MAX(procedure_count) AS max_procedure_count
  FROM procedure_burden
),

-- Hospital LOS and in-hospital mortality for the specific group
los_mortality AS (
  SELECT 
    a.hadm_id,
    a.dischtime,
    a.admittime,
    a.hospital_expire_flag
  FROM patients_ich p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.hadm_id = a.hadm_id
),

-- General ICU population for comparison
general_icu AS (
  SELECT 
    i.hadm_id,
    a.dischtime,
    a.admittime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
)

-- Final calculations
SELECT 
  p25,
  p50,
  p90,
  max_procedure_count,
  AVG(TIMESTAMP_DIFF(lm.dischtime, lm.admittime, DAY)) AS los_ich,
  SUM(CASE WHEN lm.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(lm.hadm_id) AS mortality_ich,
  AVG(TIMESTAMP_DIFF(g.dischtime, g.admittime, DAY)) AS los_general,
  SUM(CASE WHEN g.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(g.hadm_id) AS mortality_general
FROM percentiles
CROSS JOIN (
  SELECT 
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(hadm_id) AS mortality
  FROM los_mortality
) AS los_mortality_stats
CROSS JOIN (
  SELECT 
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS los_general,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(hadm_id) AS mortality_general
  FROM general_icu
) AS general_icu_stats;