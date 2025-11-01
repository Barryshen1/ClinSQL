WITH ards_icd_codes AS (
  -- ARDS ICD-9 and ICD-10 codes
  SELECT '51882' AS icd_code, 9 AS icd_version UNION ALL
  SELECT 'J80' AS icd_code, 10 AS icd_version
),
ards_patients AS (
  -- ICU stays for female, age 84-94, with ARDS diagnosis
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.hadm_id = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON icu.hadm_id = diag.hadm_id
    JOIN ards_icd_codes ards
      ON diag.icd_code = ards.icd_code AND diag.icd_version = ards.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
),
general_icu AS (
  -- All ICU stays
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.hadm_id = adm.hadm_id
),
procedures_24h AS (
  -- Diagnostic intensity: count distinct procedures in first 24h of ICU stay
  SELECT
    cohort,
    stay_id,
    COUNT(DISTINCT proc.icd_code) AS n_distinct_procedures
  FROM (
    SELECT 'ARDS_F84_94' AS cohort, stay_id, hadm_id, intime FROM ards_patients
    UNION ALL
    SELECT 'GENERAL_ICU' AS cohort, stay_id, hadm_id, intime FROM general_icu
  ) icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON icu.hadm_id = proc.hadm_id
    AND proc.chartdate >= icu.intime
    AND proc.chartdate < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY cohort, stay_id
),
cohort_info AS (
  -- Add hospital LOS and mortality
  SELECT
    icu.cohort,
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    proc.n_distinct_procedures,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS hosp_los,
    adm.hospital_expire_flag
  FROM (
    SELECT 'ARDS_F84_94' AS cohort, stay_id, subject_id, hadm_id FROM ards_patients
    UNION ALL
    SELECT 'GENERAL_ICU' AS cohort, stay_id, subject_id, hadm_id FROM general_icu
  ) icu
  LEFT JOIN procedures_24h proc
    ON icu.cohort = proc.cohort AND icu.stay_id = proc.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
)
SELECT
  cohort,
  COUNT(*) AS n_patients,
  APPROX_QUANTILES(IFNULL(n_distinct_procedures, 0), 100)[25] AS diagnostic_intensity_p25,
  APPROX_QUANTILES(IFNULL(n_distinct_procedures, 0), 100)[75] AS diagnostic_intensity_p75,
  APPROX_QUANTILES(IFNULL(n_distinct_procedures, 0), 100)[95] AS diagnostic_intensity_p95,
  ROUND(AVG(hosp_los), 2) AS avg_hosp_los,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4) AS hosp_mortality_rate
FROM
  cohort_info
GROUP BY cohort
ORDER BY cohort;