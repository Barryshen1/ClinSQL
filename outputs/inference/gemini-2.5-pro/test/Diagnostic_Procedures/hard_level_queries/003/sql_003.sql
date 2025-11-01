WITH
  -- Step 1: Identify all hospital admissions with an ARDS diagnosis
  ArdsHadms AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- J80 is the ICD-10 code for ARDS
      -- 51882 is the ICD-9 code for ARDS
      icd_code IN ('J80', '51882')
  ),
  -- Step 2: Identify the specific target cohort of ICU stays
  TargetCohortStays AS (
    SELECT
      i.stay_id,
      i.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON i.subject_id = p.subject_id
    -- Ensure the admission had an ARDS diagnosis
    INNER JOIN ArdsHadms AS a
      ON i.hadm_id = a.hadm_id
    WHERE
      p.gender = 'F'
      -- Calculate age at ICU admission for precise filtering
      AND (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 84 AND 94
  ),
  -- Step 3: Calculate the number of distinct procedures in the first 24h for all ICU stays
  ProceduresFirst24h AS (
    SELECT
      i.stay_id,
      COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON i.stay_id = pe.stay_id
    WHERE
      pe.starttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    GROUP BY
      i.stay_id
  ),
  -- Step 4: Aggregate per-stay metrics (procedure intensity) for the Target Cohort
  TargetProcAgg AS (
    SELECT
      'Female, 84-94, ARDS' AS cohort_group,
      APPROX_QUANTILES(COALESCE(p24.num_procedures, 0), 100)[OFFSET(25)] AS p25_diagnostic_intensity,
      APPROX_QUANTILES(COALESCE(p24.num_procedures, 0), 100)[OFFSET(75)] AS p75_diagnostic_intensity,
      APPROX_QUANTILES(COALESCE(p24.num_procedures, 0), 100)[OFFSET(95)] AS p95_diagnostic_intensity
    FROM TargetCohortStays AS tcs
    LEFT JOIN ProceduresFirst24h AS p24
      ON tcs.stay_id = p24.stay_id
  ),
  -- Step 5: Aggregate per-admission metrics (LOS, mortality) for the Target Cohort
  TargetHospAgg AS (
    SELECT
      AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los,
      AVG(a.hospital_expire_flag) * 100 AS hospital_mortality_pct
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    -- Filter admissions to only those belonging to the target cohort
    WHERE
      a.hadm_id IN (
        SELECT DISTINCT hadm_id FROM TargetCohortStays
      )
  ),
  -- Step 6: Aggregate per-stay metrics (procedure intensity) for the General ICU Population
  GeneralProcAgg AS (
    SELECT
      'General ICU Population' AS cohort_group,
      APPROX_QUANTILES(COALESCE(p24.num_procedures, 0), 100)[OFFSET(25)] AS p25_diagnostic_intensity,
      APPROX_QUANTILES(COALESCE(p24.num_procedures, 0), 100)[OFFSET(75)] AS p75_diagnostic_intensity,
      APPROX_QUANTILES(COALESCE(p24.num_procedures, 0), 100)[OFFSET(95)] AS p95_diagnostic_intensity
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    LEFT JOIN ProceduresFirst24h AS p24
      ON i.stay_id = p24.stay_id
  ),
  -- Step 7: Aggregate per-admission metrics (LOS, mortality) for the General ICU Population
  GeneralHospAgg AS (
    SELECT
      AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los,
      AVG(a.hospital_expire_flag) * 100 AS hospital_mortality_pct
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    -- Filter admissions to only those that had an ICU stay
    WHERE
      a.hadm_id IN (
        SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
      )
  )
-- Step 8: Combine the results for both cohorts
SELECT
  target.cohort_group,
  target.p25_diagnostic_intensity,
  target.p75_diagnostic_intensity,
  target.p95_diagnostic_intensity,
  hosp.avg_hospital_los,
  hosp.hospital_mortality_pct
FROM TargetProcAgg AS target
CROSS JOIN TargetHospAgg AS hosp
UNION ALL
SELECT
  general.cohort_group,
  general.p25_diagnostic_intensity,
  general.p75_diagnostic_intensity,
  general.p95_diagnostic_intensity,
  hosp.avg_hospital_los,
  hosp.hospital_mortality_pct
FROM GeneralProcAgg AS general
CROSS JOIN GeneralHospAgg AS hosp;