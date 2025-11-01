WITH
  all_icu_patients AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON i.hadm_id = a.hadm_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 50 AND 60
  ),
  ich_diagnoses AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes
      (icd_version = 9 AND icd_code IN ('430', '431', '432')) OR
      -- ICD-10 codes
      (icd_version = 10 AND icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%')
  ),
  cohort_with_ich_flag AS (
    SELECT
      aip.*,
      CASE WHEN id.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS ich_flag
    FROM all_icu_patients aip
    LEFT JOIN ich_diagnoses id
      ON aip.hadm_id = id.hadm_id
  ),
  -- Procedure burden for ICH cohort (per ICU stay)
  ich_procedure_burden AS (
    SELECT
      c.stay_id,
      COUNT(pe.itemid) AS procedure_count
    FROM cohort_with_ich_flag c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON c.stay_id = pe.stay_id
    WHERE
      c.ich_flag = 1
      AND pe.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.stay_id
  ),
  procedure_burden_stats AS (
    SELECT
      APPROX_QUANTILES(procedure_count, 100) AS percentiles,
      MAX(procedure_count) AS max_count
    FROM ich_procedure_burden
  ),
  -- Deduplicate to admission level for LOS/mortality
  admission_level_cohort AS (
    SELECT
      hadm_id,
      MAX(ich_flag) AS ich_flag,  -- 1 if any ICH diagnosis in admission
      MAX(los_hospital) AS los_hospital,  -- LOS is per admission
      MAX(hospital_expire_flag) AS hospital_expire_flag  -- Mortality flag
    FROM cohort_with_ich_flag
    GROUP BY hadm_id
  ),
  los_mortality_stats AS (
    SELECT
      CASE
        WHEN ich_flag = 1 THEN 'ICH'
        ELSE 'Control'
      END AS cohort_group,
      APPROX_QUANTILES(los_hospital, 100) AS los_percentiles,
      MAX(los_hospital) AS max_los,
      SUM(hospital_expire_flag) AS mortality_count,
      COUNT(*) AS total_admissions,
      ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate
    FROM admission_level_cohort
    GROUP BY ich_flag
  )
-- Final output: Part 1 (Procedure burden) and Part 2 (LOS & Mortality)
SELECT
  'Procedure Burden' AS metric,
  'ICH' AS cohort_group,
  (SELECT percentiles[OFFSET(25)] FROM procedure_burden_stats) AS p25,
  (SELECT percentiles[OFFSET(50)] FROM procedure_burden_stats) AS p50,
  (SELECT percentiles[OFFSET(90)] FROM procedure_burden_stats) AS p90,
  (SELECT max_count FROM procedure_burden_stats) AS max_value,
  NULL AS mortality_count,
  NULL AS mortality_rate
UNION ALL
SELECT
  'Hospital LOS and Mortality' AS metric,
  cohort_group,
  los_percentiles[OFFSET(25)] AS p25,
  los_percentiles[OFFSET(50)] AS p50,
  los_percentiles[OFFSET(90)] AS p90,
  max_los AS max_value,
  mortality_count,
  mortality_rate
FROM los_mortality_stats;