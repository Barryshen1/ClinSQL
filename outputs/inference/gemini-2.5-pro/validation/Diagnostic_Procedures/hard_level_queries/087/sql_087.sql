WITH
  -- Step 1: Identify hospital admissions with an Intracranial Hemorrhage (ICH) diagnosis
  ich_hadms AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (
        icd_version = 9
        AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432')
      )
      OR (
        icd_version = 10
        AND SUBSTR(icd_code, 1, 4) IN ('I60.', 'I61.', 'I62.')
      )
  ),

  -- Step 2: Define the primary cohort of female patients, aged 56-66, with ICH, during their ICU stay
  cohort_stays AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      DATETIME_ADD(icu.intime, INTERVAL 72 HOUR) AS endtime_72h,
      icu.los,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
    INNER JOIN ich_hadms
      ON icu.hadm_id = ich_hadms.hadm_id
    WHERE
      pat.gender = 'F'
      AND (
        (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) + pat.anchor_age
      ) BETWEEN 56 AND 66
  ),

  -- Step 3: Calculate total diagnostic events per stay within the first 72 hours.
  -- This is restructured to use correlated subqueries to correctly count events
  -- from each table, avoiding the "fan-out" issue of the original multi-table JOIN.
  diagnostic_totals_per_stay AS (
    SELECT
      cs.stay_id,
      cs.los,
      cs.hospital_expire_flag,
      (
        (
          SELECT COUNT(DISTINCT le.labevent_id)
          FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
          WHERE le.hadm_id = cs.hadm_id AND le.charttime BETWEEN cs.intime AND cs.endtime_72h
        )
        + (
          SELECT COUNT(DISTINCT me.microevent_id)
          FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` AS me
          WHERE me.hadm_id = cs.hadm_id AND me.charttime BETWEEN cs.intime AND cs.endtime_72h
        )
        + (
          -- FIX: procedureevents lacks a unique ID. We count rows within the subquery
          -- to get an accurate count of procedure administrations.
          SELECT COUNT(*)
          FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
          WHERE pe.stay_id = cs.stay_id AND pe.starttime BETWEEN cs.intime AND cs.endtime_72h
        )
      ) AS total_diagnostic_events
    FROM
      cohort_stays AS cs
  ),

  -- Step 4: Aggregate all metrics for the cohort using standard aggregate functions
  cohort_results AS (
    SELECT
      'ICH Cohort (Female, 56-66)' AS cohort_description,
      -- Use APPROX_QUANTILES for efficient percentile calculation in an aggregation
      APPROX_QUANTILES(dt.total_diagnostic_events, 100)[OFFSET(95)] AS diagnostic_intensity_95th_percentile,
      AVG(dt.los) AS avg_icu_los,
      AVG(CAST(dt.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
    FROM diagnostic_totals_per_stay AS dt
  ),

  -- Step 5: Calculate comparative metrics for the general ICU population
  general_icu_results AS (
    SELECT
      'All ICU Patients' AS cohort_description,
      NULL AS diagnostic_intensity_95th_percentile,
      AVG(icu.los) AS avg_icu_los,
      AVG(CAST(adm.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
    GROUP BY
      cohort_description
  )

-- Step 6: Combine the results from both groups
SELECT
  cohort_description,
  diagnostic_intensity_95th_percentile,
  avg_icu_los,
  in_hospital_mortality_rate
FROM cohort_results
UNION ALL
SELECT
  cohort_description,
  diagnostic_intensity_95th_percentile,
  avg_icu_los,
  in_hospital_mortality_rate
FROM general_icu_results;