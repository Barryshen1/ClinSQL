WITH target_patients AS (
  SELECT DISTINCT p.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),

copd_admissions AS (
  SELECT DISTINCT tp.subject_id, hadm_id
  FROM target_patients tp
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON tp.subject_id = di.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code IN ('491.21', 'J44.1')
),

icu_stays_target AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    DATETIME_DIFF(icu.outtime, icu.intime, HOUR) / 24.0 AS icu_los_days,
    adm.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN copd_admissions ca
    ON icu.hadm_id = ca.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
),

procedures_first_72h AS (
  SELECT
    ist.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM icu_stays_target ist
  JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON ist.stay_id = pe.stay_id
  WHERE pe.starttime >= ist.intime
    AND pe.starttime <= DATETIME_ADD(ist.intime, INTERVAL 72 HOUR)
  GROUP BY ist.stay_id
),

percentile_75 AS (
  SELECT
    APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(75)] AS p75_distinct_procedures
  FROM procedures_first_72h
),

all_icu_stays_age_matched AS (
  SELECT
    icu.stay_id,
    icu.intime,
    icu.outtime,
    DATETIME_DIFF(icu.outtime, icu.intime, HOUR) / 24.0 AS icu_los_days,
    adm.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN target_patients tp
    ON icu.subject_id = tp.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
),

target_stats AS (
  SELECT
    AVG(icu_los_days) AS mean_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM icu_stays_target
),

all_stats AS (
  SELECT
    AVG(icu_los_days) AS mean_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM all_icu_stays_age_matched
)

SELECT
  (SELECT p75_distinct_procedures FROM percentile_75) AS p75_distinct_procedures_72h,
  ts.mean_icu_los AS target_mean_icu_los,
  ts.mortality_rate AS target_mortality_rate,
  als.mean_icu_los AS all_mean_icu_los,
  als.mortality_rate AS all_mortality_rate
FROM target_stats ts
CROSS JOIN all_stats als;