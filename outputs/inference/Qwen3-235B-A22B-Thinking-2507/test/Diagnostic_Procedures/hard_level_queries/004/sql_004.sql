WITH icd_cohort AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'I60%' 
     OR icd_code LIKE 'I61%' 
     OR icd_code LIKE 'I62%'
),
cohort_base AS (
  SELECT 
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  INNER JOIN icd_cohort icd
    ON a.hadm_id = icd.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),
cohort_procedures AS (
  SELECT 
    cb.stay_id,
    cb.los,
    cb.hospital_expire_flag,
    COUNT(pe.stay_id) AS procedure_count
  FROM cohort_base cb
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON cb.stay_id = pe.stay_id
    AND pe.starttime >= cb.intime
    AND pe.starttime <= cb.intime + INTERVAL '72' HOUR
  GROUP BY cb.stay_id, cb.los, cb.hospital_expire_flag
),
general_icu AS (
  SELECT 
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
)
SELECT
  (SELECT APPROX_QUANTILES(procedure_count, 1000)[OFFSET(250)] FROM cohort_procedures) AS procedure_burden_25,
  (SELECT APPROX_QUANTILES(procedure_count, 1000)[OFFSET(500)] FROM cohort_procedures) AS procedure_burden_50,
  (SELECT APPROX_QUANTILES(procedure_count, 1000)[OFFSET(900)] FROM cohort_procedures) AS procedure_burden_90,
  (SELECT APPROX_QUANTILES(los, 1000)[OFFSET(500)] FROM cohort_procedures) AS cohort_icu_los_median,
  (SELECT AVG(hospital_expire_flag) FROM cohort_procedures) AS cohort_mortality_rate,
  (SELECT APPROX_QUANTILES(los, 1000)[OFFSET(500)] FROM general_icu) AS general_icu_los_median,
  (SELECT AVG(hospital_expire_flag) FROM general_icu) AS general_mortality_rate;