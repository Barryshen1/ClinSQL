WITH
-- 1. Identify PE ICD codes
pe_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%pulmonary embolism%'
),

-- 2. ICU stays with patient demographics
icu_patients AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
),

-- 3. Identify PE patients
pe_patients AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN pe_icd
    ON d.icd_code = pe_icd.icd_code AND d.icd_version = pe_icd.icd_version
),

-- 4. Diagnostic utilization score for each ICU stay
diagnostic_events AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    COUNT(DISTINCT lab.labevent_id) AS lab_events,
    COUNT(DISTINCT micro.microevent_id) AS micro_events,
    COUNT(DISTINCT proc.icd_code) AS proc_events
  FROM icu_patients icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON icu.subject_id = lab.subject_id
    AND icu.hadm_id = lab.hadm_id
    AND lab.charttime >= icu.intime
    AND lab.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
    ON icu.subject_id = micro.subject_id
    AND icu.hadm_id = micro.hadm_id
    AND micro.charttime >= icu.intime
    AND micro.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON icu.subject_id = proc.subject_id
    AND icu.hadm_id = proc.hadm_id
    AND proc.chartdate >= DATE(icu.intime)
    AND proc.chartdate < DATE(DATETIME_ADD(icu.intime, INTERVAL 1 DAY))
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),

diagnostic_score AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    icu.gender,
    icu.anchor_age,
    COALESCE(de.lab_events, 0) + COALESCE(de.micro_events, 0) + COALESCE(de.proc_events, 0) AS diagnostic_score
  FROM icu_patients icu
  LEFT JOIN diagnostic_events de
    ON icu.subject_id = de.subject_id
    AND icu.hadm_id = de.hadm_id
    AND icu.stay_id = de.stay_id
),

-- 5. Add hospital mortality
icu_with_mortality AS (
  SELECT
    ds.*,
    a.hospital_expire_flag
  FROM diagnostic_score ds
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ds.subject_id = a.subject_id AND ds.hadm_id = a.hadm_id
),

-- 6. Target cohort: male, age 79-89, PE
target_cohort AS (
  SELECT *
  FROM icu_with_mortality
  WHERE gender = 'M'
    AND anchor_age BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1 FROM pe_patients pe
      WHERE pe.subject_id = icu_with_mortality.subject_id
        AND pe.hadm_id = icu_with_mortality.hadm_id
    )
),

-- 7. General ICU cohort
general_cohort AS (
  SELECT *
  FROM icu_with_mortality
)

-- 8. Aggregate results using cross join of single-row subqueries
SELECT
  t.diagnostic_score_75th_percentile,
  t.target_median_icu_los,
  g.general_median_icu_los,
  t.target_hospital_mortality_rate,
  g.general_hospital_mortality_rate
FROM
  -- Target cohort stats
  (
    SELECT
      -- 75th percentile diagnostic utilization score
      PERCENTILE_CONT(diagnostic_score, 0.75) AS diagnostic_score_75th_percentile,
      -- Median ICU LOS
      PERCENTILE_CONT(los, 0.5) AS target_median_icu_los,
      -- Hospital mortality rate
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS target_hospital_mortality_rate
    FROM target_cohort
  ) t
CROSS JOIN
  -- General cohort stats
  (
    SELECT
      PERCENTILE_CONT(los, 0.5) AS general_median_icu_los,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS general_hospital_mortality_rate
    FROM general_cohort
  ) g
LIMIT 1;