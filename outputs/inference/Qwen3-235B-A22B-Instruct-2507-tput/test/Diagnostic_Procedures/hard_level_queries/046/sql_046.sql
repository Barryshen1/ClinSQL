WITH ards_code AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute respiratory distress syndrome%'
    AND icd_version = 10
),
first_icu_stays AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) AS stay_order
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
),
ards_patients AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    fis.stay_id,
    fis.intime,
    fis.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN ards_code ac
    ON di.icd_code = ac.icd_code AND di.icd_version = 10
  INNER JOIN first_icu_stays fis
    ON a.hadm_id = fis.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND fis.stay_order = 1
),
procedure_counts AS (
  SELECT 
    fis.stay_id,
    fis.subject_id,
    fis.intime,
    fis.outtime,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fis.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fis.stay_id = pe.stay_id
    AND pe.starttime >= fis.intime
    AND pe.starttime <= DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
    AND pe.starttime <= COALESCE(fis.outtime, DATETIME_ADD(fis.intime, INTERVAL 72 HOUR))
  WHERE fis.stay_order = 1
  GROUP BY fis.stay_id, fis.subject_id, fis.intime, fis.outtime, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
ards_cohort_stats AS (
  SELECT 
    MIN(pc.distinct_procedure_count) AS min_diagnostic_utilization
  FROM procedure_counts pc
  INNER JOIN ards_patients ap
    ON pc.stay_id = ap.stay_id
),
all_icu_stats AS (
  SELECT 
    APPROX_QUANTILES(pc.distinct_procedure_count, 1000)[OFFSET(750)] AS p75_procedures,
    APPROX_QUANTILES(pc.distinct_procedure_count, 1000)[OFFSET(900)] AS p90_procedures,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(a.hospital_expire_flag) AS in_hospital_mortality_rate
  FROM procedure_counts pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pc.hadm_id = a.hadm_id
)
SELECT 
  acs.min_diagnostic_utilization,
  ais.p75_procedures,
  ais.p90_procedures,
  ais.mean_los_days,
  ais.in_hospital_mortality_rate
FROM ards_cohort_stats acs
CROSS JOIN all_icu_stats ais;