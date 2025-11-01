WITH status_epilepticus AS (
  SELECT 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '3453')  -- ICD-9 code for status epilepticus
     OR (icd_version = 10 AND icd_code = 'R561') -- ICD-10 code for status epilepticus
  GROUP BY hadm_id
),

icu_patients AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    i.intime,
    i.outtime,
    i.los,  -- ADDED: ICU length of stay from icustays table
    p.gender,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission,
    -- Flag if they have status epilepticus
    CASE WHEN se.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_status_epilepticus,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN status_epilepticus se
    ON i.hadm_id = se.hadm_id
),

cohort1 AS (
  SELECT *
  FROM icu_patients
  WHERE gender = 'F'
    AND age_at_admission BETWEEN 63 AND 73
    AND has_status_epilepticus = 1
),

cohort2 AS (
  SELECT *
  FROM icu_patients
),

vitals_cohort1 AS (
  SELECT 
    c1.stay_id,
    ce.charttime,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS hr,  -- Heart Rate
    MAX(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END) AS map  -- MAP
  FROM cohort1 c1
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c1.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c1.intime AND c1.intime + INTERVAL '72' HOUR
    AND ce.itemid IN (220045, 220052)
  GROUP BY c1.stay_id, ce.charttime
),

instability_index_cohort1 AS (
  SELECT 
    stay_id,
    AVG(CASE WHEN hr > 100 OR map < 65 THEN 1 ELSE 0 END) AS vital_instability_index
  FROM vitals_cohort1
  GROUP BY stay_id
),

vitals_all AS (
  SELECT 
    icu.stay_id,
    'cohort1' AS cohort_type,
    ce.charttime,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS hr,
    MAX(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END) AS map
  FROM cohort1 icu
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
    AND ce.charttime BETWEEN icu.intime AND icu.intime + INTERVAL '72' HOUR
    AND ce.itemid IN (220045, 220052)
  GROUP BY icu.stay_id, ce.charttime
  
  UNION ALL
  
  SELECT 
    icu.stay_id,
    'cohort2' AS cohort_type,
    ce.charttime,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS hr,
    MAX(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END) AS map
  FROM cohort2 icu
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
    AND ce.charttime BETWEEN icu.intime AND icu.intime + INTERVAL '72' HOUR
    AND ce.itemid IN (220045, 220052)
  GROUP BY icu.stay_id, ce.charttime
),

burden_metrics AS (
  SELECT
    cohort_type,
    AVG(CASE WHEN hr > 100 THEN 1 ELSE 0 END) AS tachycardia_burden,
    AVG(CASE WHEN map < 65 THEN 1 ELSE 0 END) AS map65_burden
  FROM vitals_all
  GROUP BY cohort_type
),

los_mortality AS (
  SELECT
    'cohort1' AS cohort_type,
    AVG(los) AS icu_los_mean,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS icu_los_median,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort1
  GROUP BY cohort_type
  
  UNION ALL
  
  SELECT
    'cohort2' AS cohort_type,
    AVG(los) AS icu_los_mean,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS icu_los_median,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort2
  GROUP BY cohort_type
)

-- Final result: vital-instability index statistics for cohort1
SELECT
  'cohort1' AS cohort,
  AVG(vital_instability_index) AS mean_vital_instability,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(90)] AS p90
FROM instability_index_cohort1

UNION ALL

-- Comparison metrics for both cohorts
SELECT
  bm.cohort_type AS cohort,
  bm.tachycardia_burden,
  bm.map65_burden,
  lm.icu_los_mean,
  lm.icu_los_median,
  lm.mortality_rate
FROM burden_metrics bm
JOIN los_mortality lm
  ON bm.cohort_type = lm.cohort_type;