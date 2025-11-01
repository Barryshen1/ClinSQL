WITH admission_age AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
),

ich_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code = '431')
     OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I61')
),

ich_cohort AS (
  SELECT DISTINCT aa.subject_id
  FROM admission_age aa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON aa.hadm_id = diag.hadm_id
  JOIN ich_codes ic
    ON diag.icd_code = ic.icd_code AND diag.icd_version = ic.icd_version
  WHERE aa.gender = 'F'
    AND aa.age_at_admission >= 50 AND aa.age_at_admission <= 60
),

ich_icu_stays AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.los AS icu_los_days,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  JOIN ich_cohort ich
    ON ie.subject_id = ich.subject_id
),

ich_procedure_burden AS (
  SELECT
    iis.stay_id,
    iis.icu_los_days,
    iis.hospital_expire_flag,
    COUNT(proc.itemid) AS procedure_count_72h
  FROM ich_icu_stays iis
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON iis.stay_id = proc.stay_id
    AND proc.starttime >= iis.intime
    AND proc.starttime <= DATETIME_ADD(iis.intime, INTERVAL 72 HOUR)
  GROUP BY iis.stay_id, iis.icu_los_days, iis.hospital_expire_flag
),

general_icu_stays AS (
  SELECT
    ie.stay_id,
    ie.intime,
    ie.los AS icu_los_days,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
),

general_procedure_burden AS (
  SELECT
    gis.stay_id,
    gis.icu_los_days,
    gis.hospital_expire_flag,
    COUNT(proc.itemid) AS procedure_count_72h
  FROM general_icu_stays gis
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON gis.stay_id = proc.stay_id
    AND proc.starttime >= gis.intime
    AND proc.starttime <= DATETIME_ADD(gis.intime, INTERVAL 72 HOUR)
  GROUP BY gis.stay_id, gis.icu_los_days, gis.hospital_expire_flag
),

ich_summary AS (
  SELECT
    APPROX_PERCENTILE(procedure_count_72h, 0.25) AS ich_procedure_25th,
    APPROX_PERCENTILE(procedure_count_72h, 0.50) AS ich_procedure_50th,
    APPROX_PERCENTILE(procedure_count_72h, 0.90) AS ich_procedure_90th,
    APPROX_QUANTILES(icu_los_days, 100)[OFFSET(50)] AS ich_icu_los_median,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS ich_mortality_rate
  FROM ich_procedure_burden
),

general_summary AS (
  SELECT
    APPROX_QUANTILES(icu_los_days, 100)[OFFSET(50)] AS general_icu_los_median,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS general_mortality_rate
  FROM general_procedure_burden
)

SELECT
  ich_procedure_25th,
  ich_procedure_50th,
  ich_procedure_90th,
  ich_icu_los_median,
  general_icu_los_median,
  ich_mortality_rate,
  general_mortality_rate
FROM ich_summary, general_summary;