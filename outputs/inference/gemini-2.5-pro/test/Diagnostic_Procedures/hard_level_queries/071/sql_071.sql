WITH
-- CTE to define the specific cohort: female ICU patients aged 50-60 with ICH
ich_cohort_stays AS (
  SELECT DISTINCT
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON icu.hadm_id = dx.hadm_id
  WHERE
    p.gender = 'F'
    AND (
      -- Calculate age at the time of ICU admission
      DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age
    ) BETWEEN 50 AND 60
    AND (
      -- ICD codes for non-traumatic intracranial hemorrhage (ICD-9 and ICD-10)
      dx.icd_code LIKE 'I60%'      -- Nontraumatic subarachnoid hemorrhage
      OR dx.icd_code LIKE 'I61%'   -- Nontraumatic intracerebral hemorrhage
      OR dx.icd_code LIKE 'I62%'   -- Other nontraumatic intracranial hemorrhage
      OR dx.icd_code IN ('430', '431', '432') -- Equivalent ICD-9 codes
    )
),

-- CTE to count procedures in the first 72 hours for each stay in the ICH cohort
ich_procedure_counts AS (
  SELECT
    ich.stay_id,
    -- Count procedures that started within the first 72 hours of ICU admission
    COUNT(pe.itemid) AS num_procedures
  FROM ich_cohort_stays AS ich
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON ich.stay_id = pe.stay_id
    AND pe.starttime BETWEEN ich.intime AND DATETIME_ADD(ich.intime, INTERVAL 72 HOUR)
  GROUP BY
    ich.stay_id
),

-- CTE to pre-calculate summary stats (LOS, mortality) for all ICU stays
-- and flag which stays belong to the ICH cohort
icu_summary_stats AS (
  SELECT
    icu.stay_id,
    -- Calculate hospital LOS in days, ensuring times are not null
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los_days,
    adm.hospital_expire_flag,
    -- Flag for belonging to the specific ICH cohort
    CASE
      WHEN ich.stay_id IS NOT NULL THEN 1
      ELSE 0
    END AS is_ich_cohort
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  LEFT JOIN ich_cohort_stays AS ich
    ON icu.stay_id = ich.stay_id
  WHERE adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
)

-- Final query to assemble the results for both cohorts
-- Part 1: ICH cohort statistics
SELECT
  'ICH Cohort (Female, 50-60)' AS cohort,
  (SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] FROM ich_procedure_counts) AS percentile_25_procedures,
  (SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] FROM ich_procedure_counts) AS percentile_50_procedures,
  (SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] FROM ich_procedure_counts) AS percentile_90_procedures,
  (SELECT MAX(num_procedures) FROM ich_procedure_counts) AS max_procedures,
  (SELECT AVG(hospital_los_days) FROM icu_summary_stats WHERE is_ich_cohort = 1) AS avg_hospital_los_days,
  (SELECT AVG(hospital_expire_flag) * 100 FROM icu_summary_stats WHERE is_ich_cohort = 1) AS in_hospital_mortality_percent

UNION ALL

-- Part 2: General ICU statistics for comparison
SELECT
  'General ICU' as cohort,
  NULL AS percentile_25_procedures,
  NULL AS percentile_50_procedures,
  NULL AS percentile_90_procedures,
  NULL AS max_procedures,
  (SELECT AVG(hospital_los_days) FROM icu_summary_stats) AS avg_hospital_los_days,
  (SELECT AVG(hospital_expire_flag) * 100 FROM icu_summary_stats) AS in_hospital_mortality_percent;