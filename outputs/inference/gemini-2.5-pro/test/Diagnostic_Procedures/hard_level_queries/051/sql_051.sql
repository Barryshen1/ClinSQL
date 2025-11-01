WITH
-- Step 1: Identify all hospital admissions (hadm_id) for the target population
sepsis_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON d.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (
      -- Sepsis-related ICD-9 codes
      (d.icd_version = 9 AND d.icd_code IN ('99591', '99592', '78552'))
      -- Sepsis-related ICD-10 codes
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65.2%'))
    )
),

-- Step 2: Get all ICU stays and associated hospital outcomes for those admissions
cohort_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN sepsis_hadm sh
    ON i.hadm_id = sh.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON i.hadm_id = adm.hadm_id
),

-- Step 3: Count lab tests in the first 24h of each ICU stay
lab_counts AS (
  SELECT
    cs.stay_id,
    COUNT(le.labevent_id) AS num_labs
  FROM cohort_stays AS cs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON cs.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
  GROUP BY
    cs.stay_id
),

-- Step 4: Count microbiology tests in the first 24h of each ICU stay
micro_counts AS (
  SELECT
    cs.stay_id,
    COUNT(me.microevent_id) AS num_micro
  FROM cohort_stays AS cs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` AS me
    ON cs.hadm_id = me.hadm_id
  WHERE
    me.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
  GROUP BY
    cs.stay_id
),

-- Step 5: Combine base cohort data with diagnostic counts for each stay
stay_level_data AS (
  SELECT
    cs.hadm_id,
    cs.stay_id,
    cs.los,
    cs.hospital_los,
    cs.hospital_expire_flag,
    COALESCE(lc.num_labs, 0) + COALESCE(mc.num_micro, 0) AS total_diagnostics
  FROM cohort_stays AS cs
  LEFT JOIN lab_counts AS lc
    ON cs.stay_id = lc.stay_id
  LEFT JOIN micro_counts AS mc
    ON cs.stay_id = mc.stay_id
)

-- Step 6: Calculate final aggregate metrics from the combined stay-level data
SELECT
  -- Diagnostic utilization stats (calculated per ICU stay)
  ROUND(STDDEV(sld.total_diagnostics), 2) AS sd_diagnostic_utilization,
  APPROX_QUANTILES(sld.total_diagnostics, 100)[OFFSET(75)] AS p75_diagnostic_utilization,
  APPROX_QUANTILES(sld.total_diagnostics, 100)[OFFSET(95)] AS p95_diagnostic_utilization,

  -- Hospital-level outcomes (calculated per unique hospital admission)
  ROUND(hadm_metrics.in_hospital_mortality_percent, 2) AS in_hospital_mortality_percent,
  ROUND(hadm_metrics.avg_hospital_los_days, 2) AS avg_hospital_los_days,

  -- ICU-level outcomes (calculated per ICU stay)
  ROUND(AVG(sld.los), 2) AS avg_icu_los_days,

  -- Cohort size summary
  COUNT(DISTINCT sld.hadm_id) AS count_admissions,
  COUNT(DISTINCT sld.stay_id) AS count_icu_stays

FROM
  stay_level_data AS sld,
  (
    -- Subquery to calculate metrics at the hospital admission (hadm_id) level
    -- to avoid incorrect averages due to one admission having multiple ICU stays
    SELECT
      AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
      AVG(hospital_los) AS avg_hospital_los_days
    FROM (
      SELECT DISTINCT
        hadm_id,
        hospital_expire_flag,
        hospital_los
      FROM stay_level_data
    )
  ) AS hadm_metrics
-- The cross join (,) is intentional as hadm_metrics returns a single row of aggregates
-- which we want to append to the single row of aggregates from the main query.
GROUP BY
  hadm_metrics.in_hospital_mortality_percent,
  hadm_metrics.avg_hospital_los_days;