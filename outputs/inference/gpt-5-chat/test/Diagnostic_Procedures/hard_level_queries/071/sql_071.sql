WITH
-- ICD code filter for ICH
ich_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND (icd_code LIKE '431%' OR icd_code LIKE '432%'))
     OR (icd_version = 10 AND (icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),

-- ICU stays for females age 50-60 with ICH
ich_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON icu.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON icu.hadm_id = d.hadm_id
  JOIN ich_codes c
    ON d.icd_code = c.icd_code AND d.icd_version = c.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),

-- General ICU female 50-60 cohort (no ICH filter)
general_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),

-- Procedure counts in first 72h for ICH cohort
ich_proc_counts AS (
  SELECT
    c.stay_id,
    COUNT(DISTINCT CONCAT(CAST(pe.itemid AS STRING), '-', CAST(pe.starttime AS STRING))) AS procedure_count
  FROM ich_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON c.stay_id = pe.stay_id
   AND pe.starttime >= c.intime
   AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.stay_id
),

-- Percentiles for procedure counts
ich_proc_percentiles AS (
  SELECT
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS p90,
    MAX(procedure_count) AS max_procs
  FROM ich_proc_counts
),

-- Hospital LOS and mortality for both cohorts
ich_stats AS (
  SELECT
    AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY)) AS avg_los_days,
    AVG(c.hospital_expire_flag) AS mortality_rate
  FROM ich_cohort c
),

gen_stats AS (
  SELECT
    AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY)) AS avg_los_days,
    AVG(c.hospital_expire_flag) AS mortality_rate
  FROM general_cohort c
)

SELECT
  p25, p50, p90, max_procs,
  ich_stats.avg_los_days AS ich_avg_los_days,
  ich_stats.mortality_rate AS ich_mortality_rate,
  gen_stats.avg_los_days AS general_avg_los_days,
  gen_stats.mortality_rate AS general_mortality_rate
FROM ich_proc_percentiles
CROSS JOIN ich_stats
CROSS JOIN gen_stats;