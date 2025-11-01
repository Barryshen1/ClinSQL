WITH base_patients AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    icustays.los,
    admissions.hospital_expire_flag,
    patients.anchor_age,
    patients.anchor_year,
    patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` admissions
    ON icustays.hadm_id = admissions.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE patients.gender = 'M'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 88 AND 98
),
copd_diagnoses AS (
  SELECT
    diagnoses_icd.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diagnoses_icd
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diagnoses_icd.icd_code = d_icd.icd_code
    AND diagnoses_icd.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%COPD%'
    AND d_icd.long_title LIKE '%exacerbation%'
),
copd_flag AS (
  SELECT
    base_patients.*,
    CASE WHEN copd_diagnoses.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_copd
  FROM base_patients
  LEFT JOIN copd_diagnoses
    ON base_patients.hadm_id = copd_diagnoses.hadm_id
),
copd_procedures AS (
  SELECT
    copd_flag.subject_id,
    COUNT(DISTINCT procedureevents.itemid) AS num_procedures
  FROM copd_flag
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` procedureevents
    ON copd_flag.stay_id = procedureevents.stay_id
  WHERE copd_flag.has_copd = 1
    AND procedureevents.starttime BETWEEN copd_flag.intime AND TIMESTAMP_ADD(copd_flag.intime, INTERVAL 72 HOUR)
  GROUP BY copd_flag.subject_id
),
coppd_metrics AS (
  SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY num_procedures) AS proc_75th,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM copd_flag
  LEFT JOIN copd_procedures ON copd_flag.subject_id = copd_procedures.subject_id
  WHERE copd_flag.has_copd = 1
),
non_copd_metrics AS (
  SELECT
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM copd_flag
  WHERE has_copd = 0
)
SELECT
  coppd_metrics.proc_75th,
  coppd_metrics.mean_los AS copd_mean_los,
  coppd_metrics.mortality_rate AS copd_mortality,
  non_copd_metrics.mean_los AS non_copd_mean_los,
  non_copd_metrics.mortality_rate AS non_copd_mortality
FROM coppd_metrics, non_copd_metrics;