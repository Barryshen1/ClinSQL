WITH upper_gi_codes AS (
  SELECT icd_code, icd_version
  FROM UNNEST([
    -- ICD-9 Codes
    STRUCT('578.0' AS icd_code, 9 AS icd_version),
    STRUCT('578.1', 9), STRUCT('578.9', 9), STRUCT('530.7', 9), STRUCT('530.82', 9),
    STRUCT('531.00', 9), STRUCT('531.01', 9), STRUCT('531.20', 9), STRUCT('531.21', 9),
    STRUCT('531.40', 9), STRUCT('531.41', 9), STRUCT('531.60', 9), STRUCT('531.61', 9),
    STRUCT('532.00', 9), STRUCT('532.01', 9), STRUCT('532.20', 9), STRUCT('532.21', 9),
    STRUCT('532.40', 9), STRUCT('532.41', 9), STRUCT('532.60', 9), STRUCT('532.61', 9),
    STRUCT('533.00', 9), STRUCT('533.01', 9), STRUCT('533.20', 9), STRUCT('533.21', 9),
    STRUCT('533.40', 9), STRUCT('533.41', 9), STRUCT('533.60', 9), STRUCT('533.61', 9),
    STRUCT('534.00', 9), STRUCT('534.01', 9), STRUCT('534.20', 9), STRUCT('534.21', 9),
    STRUCT('534.40', 9), STRUCT('534.41', 9), STRUCT('534.60', 9), STRUCT('534.61', 9),
    -- ICD-10 Codes
    STRUCT('K25.0', 10), STRUCT('K25.2', 10), STRUCT('K25.4', 10), STRUCT('K25.6', 10),
    STRUCT('K26.0', 10), STRUCT('K26.2', 10), STRUCT('K26.4', 10), STRUCT('K26.6', 10),
    STRUCT('K27.0', 10), STRUCT('K27.2', 10), STRUCT('K27.4', 10), STRUCT('K27.6', 10),
    STRUCT('K28.0', 10), STRUCT('K28.2', 10), STRUCT('K28.4', 10), STRUCT('K28.6', 10),
    STRUCT('K22.6', 10), STRUCT('K92.0', 10), STRUCT('K92.1', 10), STRUCT('K92.2', 10)
  ])
),
cohort_admissions AS (
  SELECT DISTINCT
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
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN upper_gi_codes gi
    ON diag.icd_code = gi.icd_code
    AND diag.icd_version = gi.icd_version
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 74 AND 84
),
first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN cohort_admissions ca
    ON i.hadm_id = ca.hadm_id
),
cohort_icu AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime
  FROM first_icu_stay
  WHERE stay_rank = 1
),
diagnostic_intensity AS (
  SELECT
    ci.stay_id,
    ci.subject_id,
    ci.hadm_id,
    COUNT(DISTINCT lab.itemid) AS lab_test_count,
    COUNT(DISTINCT micro.test_itemid) AS micro_test_count
  FROM cohort_icu ci
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON ci.hadm_id = lab.hadm_id
    AND lab.charttime >= ci.intime
    AND lab.charttime < DATETIME_ADD(ci.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
    ON ci.hadm_id = micro.hadm_id
    AND micro.charttime >= ci.intime
    AND micro.charttime < DATETIME_ADD(ci.intime, INTERVAL 72 HOUR)
  GROUP BY ci.stay_id, ci.subject_id, ci.hadm_id
),
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),
cohort_data AS (
  SELECT
    di.stay_id,
    di.subject_id,
    di.hadm_id,
    di.lab_test_count + di.micro_test_count AS test_count,
    COALESCE(pc.procedure_count, 0) AS procedure_count,
    DATETIME_DIFF(ca.dischtime, ca.admittime, DAY) AS los_hospital,
    ca.hospital_expire_flag
  FROM diagnostic_intensity di
  INNER JOIN cohort_admissions ca
    ON di.hadm_id = ca.hadm_id
  LEFT JOIN procedure_counts pc
    ON di.hadm_id = pc.hadm_id
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY test_count) AS quartile
  FROM cohort_data
)
SELECT
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los_hospital) AS mean_los_hospital_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality
FROM quartiles
GROUP BY quartile
ORDER BY quartile;