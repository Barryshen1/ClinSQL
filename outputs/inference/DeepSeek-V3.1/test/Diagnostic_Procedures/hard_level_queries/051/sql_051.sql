WITH sepsis_cohort AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag,
    -- Count distinct lab tests in first 24h
    COUNT(DISTINCT le.itemid) AS lab_test_count,
    -- Count distinct microbiology tests in first 24h
    COUNT(DISTINCT me.test_itemid) AS micro_test_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  -- Left join to labevents (first 24h)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ie.hadm_id = le.hadm_id
    AND le.charttime >= ie.intime
    AND le.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  -- Left join to microbiologyevents (first 24h)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
    ON ie.hadm_id = me.hadm_id
    AND me.charttime >= ie.intime
    AND me.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  -- Sepsis diagnosis (ICD-9 and ICD-10 codes) and demographic filters
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE ie.hadm_id = di.hadm_id
      AND (
        (di.icd_version = 9 AND di.icd_code LIKE '038%') OR
        (di.icd_version = 9 AND di.icd_code = '995.91') OR
        (di.icd_version = 9 AND di.icd_code = '995.92') OR
        (di.icd_version = 10 AND di.icd_code LIKE 'A41%') OR
        (di.icd_version = 10 AND di.icd_code LIKE 'R65.2%')
      )
  )
  AND p.anchor_age BETWEEN 90 AND 100
  AND p.gender = 'M'
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime, ie.los, adm.hospital_expire_flag
),
cohort_aggregates AS (
  SELECT
    COUNT(DISTINCT stay_id) AS n_icu_stays,
    COUNT(DISTINCT hadm_id) AS n_admissions,
    -- Total diagnostic tests (labs + micro)
    AVG(lab_test_count + micro_test_count) AS avg_dx_utilization,
    STDDEV(lab_test_count + micro_test_count) AS sd_dx_utilization,
    APPROX_QUANTILES(lab_test_count + micro_test_count, 100)[OFFSET(75)] AS p75_dx_utilization,
    APPROX_QUANTILES(lab_test_count + micro_test_count, 100)[OFFSET(95)] AS p95_dx_utilization,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent,
    AVG(los) AS avg_icu_los_days
  FROM sepsis_cohort
),
overall_icu AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_icu_admissions
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT
  n_icu_stays,
  n_admissions,
  avg_dx_utilization,
  sd_dx_utilization,
  p75_dx_utilization,
  p95_dx_utilization,
  in_hospital_mortality_percent,
  avg_icu_los_days,
  total_icu_admissions,
  n_admissions / total_icu_admissions * 100 AS admissions_percent_of_total_icu
FROM cohort_aggregates, overall_icu;