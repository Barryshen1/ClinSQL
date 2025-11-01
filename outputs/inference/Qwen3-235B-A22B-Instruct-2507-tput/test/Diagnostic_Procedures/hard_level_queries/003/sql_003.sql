WITH ards_cohort AS (
  SELECT DISTINCT icu.stay_id, icu.hadm_id, icu.intime, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(d_diag.long_title) LIKE '%acute respiratory distress syndrome%'
),
ards_procedures AS (
  SELECT 
    ac.stay_id,
    ac.hadm_id,
    COUNT(DISTINCT pe.itemid) AS diagnostic_intensity
  FROM ards_cohort ac
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ac.stay_id = pe.stay_id
    AND pe.starttime >= ac.intime
    AND pe.starttime < DATETIME_ADD(ac.intime, INTERVAL 24 HOUR)
  GROUP BY ac.stay_id, ac.hadm_id
),
ards_outcomes AS (
  SELECT 
    ap.stay_id,
    ap.diagnostic_intensity,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM ards_procedures ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ap.hadm_id = adm.hadm_id
),
general_cohort AS (
  SELECT icu.stay_id, icu.hadm_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
),
general_procedures AS (
  SELECT 
    gc.stay_id,
    gc.hadm_id,
    COUNT(DISTINCT pe.itemid) AS diagnostic_intensity
  FROM general_cohort gc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON gc.stay_id = pe.stay_id
    AND pe.starttime >= gc.intime
    AND pe.starttime < DATETIME_ADD(gc.intime, INTERVAL 24 HOUR)
  GROUP BY gc.stay_id, gc.hadm_id
),
general_outcomes AS (
  SELECT 
    gp.stay_id,
    gp.diagnostic_intensity,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM general_procedures gp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON gp.hadm_id = adm.hadm_id
),
ards_stats AS (
  SELECT
    'ARDS 84-94F' AS cohort,
    APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(25)] AS p25_procedures,
    APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(75)] AS p75_procedures,
    APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(95)] AS p95_procedures,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
  FROM ards_outcomes
),
general_stats AS (
  SELECT
    'General ICU' AS cohort,
    APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(25)] AS p25_procedures,
    APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(75)] AS p75_procedures,
    APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(95)] AS p95_procedures,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
  FROM general_outcomes
)
SELECT * FROM ards_stats
UNION ALL
SELECT * FROM general_stats;