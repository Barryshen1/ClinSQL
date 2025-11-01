WITH ich_patients AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE d.icd_version = 10
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    AND p.gender = 'F'
),
ich_patients_with_age AS (
  SELECT 
    *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM ich_patients
),
ich_patients_filtered AS (
  SELECT *
  FROM ich_patients_with_age
  WHERE age_at_admission BETWEEN 50 AND 60
),
ich_icu_stays AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN ich_patients_filtered p
    ON i.hadm_id = p.hadm_id
),
ich_procedure_burden AS (
  SELECT 
    s.stay_id,
    COUNT(p.itemid) AS procedure_burden,
    s.hospital_expire_flag,
    DATETIME_DIFF(s.dischtime, s.admittime, SECOND) / (24*3600.0) AS hospital_los
  FROM ich_icu_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON s.stay_id = p.stay_id
    AND p.starttime >= s.intime
    AND p.starttime < TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.stay_id, s.hospital_expire_flag, s.dischtime, s.admittime
),
general_icu_stays AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
),
general_procedure_burden AS (
  SELECT 
    s.stay_id,
    COUNT(p.itemid) AS procedure_burden,
    s.hospital_expire_flag,
    DATETIME_DIFF(s.dischtime, s.admittime, SECOND) / (24*3600.0) AS hospital_los
  FROM general_icu_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON s.stay_id = p.stay_id
    AND p.starttime >= s.intime
    AND p.starttime < TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.stay_id, s.hospital_expire_flag, s.dischtime, s.admittime
)
SELECT 
  'ICH' AS group_name,
  APPROX_QUANTILES(procedure_burden, 1000)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(procedure_burden, 1000)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(procedure_burden, 1000)[OFFSET(900)] AS p90,
  MAX(procedure_burden) AS max_burden,
  AVG(hospital_los) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM ich_procedure_burden

UNION ALL

SELECT 
  'General ICU',
  NULL,
  NULL,
  NULL,
  NULL,
  AVG(hospital_los),
  AVG(hospital_expire_flag)
FROM general_procedure_burden;