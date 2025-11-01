WITH
-- Get first ICU stay per patient
first_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
),
-- Add demographics and admission info
icu_patients AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.icu_intime,
    f.icu_outtime,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    first_icu_stays f
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON f.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.hadm_id = a.hadm_id
  WHERE
    f.rn = 1
),
-- Identify ARDS diagnosis (ICD-10 J80 or ICD-9 51882)
ards_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.icu_intime,
    i.icu_outtime,
    i.gender,
    i.anchor_age,
    i.admittime,
    i.dischtime,
    i.hospital_expire_flag
  FROM
    icu_patients i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON i.hadm_id = d.hadm_id
  WHERE
    ( (d.icd_version = 9 AND d.icd_code = '51882')
      OR (d.icd_version = 10 AND d.icd_code = 'J80') )
),
-- Procedures within first 72h of ICU stay
procedures_72h AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    COUNT(DISTINCT p.icd_code) AS num_distinct_procedures
  FROM
    icu_patients i
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      ON i.hadm_id = p.hadm_id
      AND p.chartdate >= i.icu_intime
      AND p.chartdate < TIMESTAMP_ADD(i.icu_intime, INTERVAL 72 HOUR)
  GROUP BY
    i.subject_id, i.hadm_id, i.stay_id
),
-- Procedures for ARDS females 37-47
ards_female_37_47 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    pr.num_distinct_procedures,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    a.hospital_expire_flag
  FROM
    ards_patients a
    INNER JOIN procedures_72h pr
      ON a.subject_id = pr.subject_id
      AND a.hadm_id = pr.hadm_id
      AND a.stay_id = pr.stay_id
  WHERE
    a.gender = 'F'
    AND a.anchor_age BETWEEN 37 AND 47
),
-- Procedures for all ICU patients
all_icu AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    pr.num_distinct_procedures,
    TIMESTAMP_DIFF(i.dischtime, i.admittime, DAY) AS hospital_los,
    i.hospital_expire_flag
  FROM
    icu_patients i
    INNER JOIN procedures_72h pr
      ON i.subject_id = pr.subject_id
      AND i.hadm_id = pr.hadm_id
      AND i.stay_id = pr.stay_id
)
-- Final statistics
SELECT
  'ARDS Female 37-47' AS cohort,
  COUNT(*) AS n_patients,
  MIN(num_distinct_procedures) AS min_diag_utilization,
  APPROX_QUANTILES(num_distinct_procedures, 100)[75] AS p75_diag_utilization,
  APPROX_QUANTILES(num_distinct_procedures, 100)[90] AS p90_diag_utilization,
  ROUND(AVG(hospital_los),2) AS mean_hospital_los,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)),4) AS in_hospital_mortality
FROM ards_female_37_47

UNION ALL

SELECT
  'All ICU' AS cohort,
  COUNT(*) AS n_patients,
  MIN(num_distinct_procedures) AS min_diag_utilization,
  APPROX_QUANTILES(num_distinct_procedures, 100)[75] AS p75_diag_utilization,
  APPROX_QUANTILES(num_distinct_procedures, 100)[90] AS p90_diag_utilization,
  ROUND(AVG(hospital_los),2) AS mean_hospital_los,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)),4) AS in_hospital_mortality
FROM all_icu;