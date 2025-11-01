WITH
  -- Step 1: Define the cohort of interest - Female ICU patients, 50-60 years old, with intracranial hemorrhage.
  ich_cohort_stays AS (
    SELECT DISTINCT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.los
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON icu.subject_id = p.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON icu.hadm_id = dx.hadm_id
    WHERE
      -- Filter for female patients
      p.gender = 'F'
      -- Filter for age at ICU admission between 50 and 60
      AND (p.anchor_age + DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)) BETWEEN 50 AND 60
      -- Filter for intracranial hemorrhage diagnoses using ICD-9 and ICD-10 codes
      AND (
        (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) IN ('430', '431', '432', '852', '853'))
        OR (
          dx.icd_version = 10 AND (
            SUBSTR(dx.icd_code, 1, 3) IN ('I60', 'I61', 'I62')
            OR SUBSTR(dx.icd_code, 1, 4) IN ('S064', 'S065', 'S066')
          )
        )
      )
  ),
  -- Step 2: Calculate procedure burden for the ICH cohort within the first 72 hours.
  ich_procedure_burden AS (
    SELECT
      ich.stay_id,
      COUNT(pe.itemid) AS procedure_count
    FROM
      ich_cohort_stays AS ich
      LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe ON ich.stay_id = pe.stay_id
      AND pe.starttime BETWEEN ich.intime AND DATETIME_ADD(ich.intime, INTERVAL 72 HOUR)
    GROUP BY
      ich.stay_id
  ),
  -- Step 3: Calculate the percentiles of procedure burden for the ICH cohort.
  ich_burden_percentiles AS (
    SELECT
      'ICH Cohort (Female, 50-60)' AS cohort_name,
      APPROX_QUANTILES(procedure_count, 100) [OFFSET (25)] AS procedure_burden_p25,
      APPROX_QUANTILES(procedure_count, 100) [OFFSET (50)] AS procedure_burden_p50,
      APPROX_QUANTILES(procedure_count, 100) [OFFSET (90)] AS procedure_burden_p90
    FROM
      ich_procedure_burden
  ),
  -- Step 4: Gather outcome data (LOS, mortality) for both the ICH cohort and the general ICU population.
  all_cohorts_outcomes AS (
    -- General ICU Population
    SELECT
      'General ICU' AS cohort_name,
      icu.los,
      adm.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON icu.hadm_id = adm.hadm_id
    UNION ALL
    -- ICH Cohort
    SELECT
      'ICH Cohort (Female, 50-60)' AS cohort_name,
      ich.los,
      adm.hospital_expire_flag
    FROM
      ich_cohort_stays AS ich
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON ich.hadm_id = adm.hadm_id
  ),
  -- Step 5: Calculate summary statistics for outcomes.
  comparison_stats AS (
    SELECT
      cohort_name,
      AVG(los) AS avg_icu_los,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_pct
    FROM
      all_cohorts_outcomes
    GROUP BY
      cohort_name
  )
-- Step 6: Final query to join the percentiles and comparison stats for the final report.
SELECT
  cs.cohort_name,
  -- Procedure burden percentiles (only for the ICH cohort)
  bp.procedure_burden_p25,
  bp.procedure_burden_p50,
  bp.procedure_burden_p90,
  -- Comparison metrics
  cs.avg_icu_los,
  cs.in_hospital_mortality_pct
FROM
  comparison_stats AS cs
  LEFT JOIN ich_burden_percentiles AS bp ON cs.cohort_name = bp.cohort_name
ORDER BY
  cs.cohort_name DESC;