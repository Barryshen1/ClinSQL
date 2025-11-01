WITH icu_cohort AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),

ards_cohort AS (
  SELECT 
    ic.stay_id,
    ic.subject_id,
    ic.hadm_id,
    ic.intime,
    ic.outtime,
    ic.gender,
    ic.anchor_age,
    ic.hospital_expire_flag,
    ic.los_hospital
  FROM icu_cohort ic
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ic.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE dd.icd_code = 'J80'  -- ICD-10 for ARDS
),

-- Count distinct procedures in first 24h for each stay
proc_counts AS (
  SELECT 
    stay_id,
    COUNT(DISTINCT itemid) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  WHERE pe.starttime >= (
    SELECT intime FROM icu_cohort ic WHERE ic.stay_id = pe.stay_id
  )
  AND pe.starttime <= DATETIME_ADD((
    SELECT intime FROM icu_cohort ic WHERE ic.stay_id = pe.stay_id
  ), INTERVAL 24 HOUR)
  GROUP BY stay_id
),

-- For ARDS cohort
ards_with_proc AS (
  SELECT 
    ac.stay_id,
    ac.hospital_expire_flag,
    ac.los_hospital,
    COALESCE(pc.num_procedures, 0) AS num_procedures
  FROM ards_cohort ac
  LEFT JOIN proc_counts pc
    ON ac.stay_id = pc.stay_id
),

-- For general cohort (all ICU patients in age/gender range)
general_with_proc AS (
  SELECT 
    ic.stay_id,
    ic.hospital_expire_flag,
    ic.los_hospital,
    COALESCE(pc.num_procedures, 0) AS num_procedures
  FROM icu_cohort ic
  LEFT JOIN proc_counts pc
    ON ic.stay_id = pc.stay_id
)

-- Aggregate for ARDS cohort
SELECT 
  'ARDS' AS cohort,
  COUNT(*) AS n_stays,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS p25_procedures,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75_procedures,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(95)] AS p95_procedures,
  AVG(los_hospital) AS avg_los_hospital,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM ards_with_proc

UNION ALL

-- Aggregate for general cohort
SELECT 
  'General' AS cohort,
  COUNT(*) AS n_stays,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS p25_procedures,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75_procedures,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(95)] AS p95_procedures,
  AVG(los_hospital) AS avg_los_hospital,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM general_with_proc;