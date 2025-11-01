WITH icu_ages AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at ICU admission
    (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 50 AND 60
),
-- Identify ICH patients
ich_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%intracranial hemorrhage%'
     OR LOWER(long_title) LIKE '%intracerebral hemorrhage%'
     OR LOWER(long_title) LIKE '%hemorrhagic stroke%'
     OR icd_code LIKE 'I61%'
     OR icd_code LIKE 'I62%'
),
ich_cohort AS (
  SELECT DISTINCT ia.*
  FROM icu_ages ia
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ia.hadm_id = di.hadm_id
  JOIN ich_codes ic
    ON di.icd_code = ic.icd_code AND di.icd_version = 10
),
-- Procedure burden in first 72 hours for ICH patients
ich_procedure_burden AS (
  SELECT 
    ip.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM ich_cohort ip
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ip.stay_id = pe.stay_id
    AND pe.starttime >= ip.intime
    AND pe.starttime <= DATETIME_ADD(ip.intime, INTERVAL 72 HOUR)
  GROUP BY ip.stay_id
),
-- General ICU cohort (same age/gender) for comparison
general_icu AS (
  SELECT 
    ia.stay_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hosp_los_days
  FROM icu_ages ia
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ia.hadm_id = a.hadm_id
),
-- ICH outcomes
ich_outcomes AS (
  SELECT 
    ipb.procedure_count,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hosp_los_days
  FROM ich_procedure_burden ipb
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON ipb.stay_id = ie.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ie.hadm_id = a.hadm_id
),
-- Summary stats for ICH procedure burden
ich_stats AS (
  SELECT
    APPROX_QUANTILES(procedure_count, 1000)[OFFSET(250)] AS p25_procedures,
    APPROX_QUANTILES(procedure_count, 1000)[OFFSET(500)] AS p50_procedures,
    APPROX_QUANTILES(procedure_count, 1000)[OFFSET(900)] AS p90_procedures,
    MAX(procedure_count) AS max_procedures
  FROM ich_procedure_burden
),
-- Average hosp LOS and mortality for ICH
ich_los_mort AS (
  SELECT
    AVG(hosp_los_days) AS avg_hosp_los_ich,
    AVG(hospital_expire_flag) AS mortality_rate_ich
  FROM ich_outcomes
),
-- Average hosp LOS and mortality for general ICU (same age/gender)
general_los_mort AS (
  SELECT
    AVG(hosp_los_days) AS avg_hosp_los_general,
    AVG(hospital_expire_flag) AS mortality_rate_general
  FROM general_icu
  WHERE admittime IS NOT NULL AND dischtime IS NOT NULL
)

-- Final output: procedure burden stats + comparison
SELECT
  p25_procedures,
  p50_procedures,
  p90_procedures,
  max_procedures,
  avg_hosp_los_ich,
  avg_hosp_los_general,
  mortality_rate_ich,
  mortality_rate_general
FROM ich_stats
CROSS JOIN ich_los_mort
CROSS JOIN general_los_mort;