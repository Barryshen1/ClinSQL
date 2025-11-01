WITH
-- ICU stays for male patients aged 79-89 with a pulmonary embolism diagnosis on the same admission
pe_cohort AS (
  SELECT DISTINCT i.*
       , a.hospital_expire_flag
       , p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
      WHERE di.hadm_id = i.hadm_id
        AND LOWER(dicd.long_title) LIKE '%pulmonary embol%'
    )
),

-- For each ICU stay in the PE cohort compute counts of diagnostic-type events in first 24 hours
pe_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    c.hospital_expire_flag,
    COALESCE((
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE le.subject_id = c.subject_id
        AND le.hadm_id = c.hadm_id
        AND le.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    ), 0) AS num_labs,
    COALESCE((
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
      WHERE me.subject_id = c.subject_id
        AND me.hadm_id = c.hadm_id
        AND me.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    ), 0) AS num_micro,
    COALESCE((
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
      WHERE hc.subject_id = c.subject_id
        AND hc.hadm_id = c.hadm_id
        -- hcpcsevents.chartdate is DATE, include if it falls within the date window covering first 24h
        AND hc.chartdate BETWEEN DATE(c.intime) AND DATE(TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR))
    ), 0) AS num_hcpcs,
    COALESCE((
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.subject_id = c.subject_id
        AND pe.hadm_id = c.hadm_id
        AND pe.stay_id = c.stay_id
        AND pe.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    ), 0) AS num_procs
  FROM pe_cohort c
),

-- Compute total diagnostic utilization score per stay
pe_scores_total AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    hospital_expire_flag,
    num_labs,
    num_micro,
    num_hcpcs,
    num_procs,
    (COALESCE(num_labs,0) + COALESCE(num_micro,0) + COALESCE(num_hcpcs,0) + COALESCE(num_procs,0)) AS total_score
  FROM pe_scores
),

-- 75th percentile of diagnostic utilization score in the PE cohort
pe_p75 AS (
  SELECT
    APPROX_QUANTILES(total_score, 100)[OFFSET(75)] AS p75_score
  FROM pe_scores_total
),

-- Metrics for PE cohort stays at or above the 75th percentile
pe_high_util_metrics AS (
  SELECT
    'PE_male_79_89_high_util' AS cohort,
    COUNT(1) AS n_stays,
    -- descriptive score stats
    AVG(total_score) AS avg_score,
    APPROX_QUANTILES(total_score, 100)[OFFSET(50)] AS median_score,
    -- ICU LOS stats
    AVG(los) AS mean_icu_los_days,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los_days,
    -- in-hospital mortality (admission-level hospital_expire_flag)
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(1)) AS inhospital_mortality_rate
  FROM pe_scores_total s
  CROSS JOIN pe_p75
  WHERE s.total_score >= pe_p75.p75_score
),

-- For comparison: overall ICU population metrics (all ICU stays)
all_icu_metrics AS (
  SELECT
    'All_ICU_population' AS cohort,
    COUNT(1) AS n_stays,
    NULL AS avg_score,       -- not applicable for general pop (score defined for PE cohort windows)
    NULL AS median_score,
    AVG(i.los) AS mean_icu_los_days,
    APPROX_QUANTILES(i.los, 100)[OFFSET(50)] AS median_icu_los_days,
    SAFE_DIVIDE(SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(1)) AS inhospital_mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
)

-- Final combined output: 75th percentile value + comparison metrics
SELECT
  'PE_male_79_89' AS cohort_label,
  (SELECT p75_score FROM pe_p75) AS pe_75th_percentile_score,
  NULL AS cohort_size,
  NULL AS avg_score,
  NULL AS median_score,
  NULL AS mean_icu_los_days,
  NULL AS median_icu_los_days,
  NULL AS inhospital_mortality_rate
UNION ALL
-- Metrics for PE cohort with high diagnostic utilization (>= 75th percentile)
SELECT
  cohort,
  (SELECT p75_score FROM pe_p75) AS pe_75th_percentile_score,
  n_stays,
  avg_score,
  median_score,
  mean_icu_los_days,
  median_icu_los_days,
  inhospital_mortality_rate
FROM pe_high_util_metrics

UNION ALL

-- Overall ICU population metrics for comparison
SELECT
  cohort,
  (SELECT p75_score FROM pe_p75) AS pe_75th_percentile_score,
  n_stays,
  avg_score,
  median_score,
  mean_icu_los_days,
  median_icu_los_days,
  inhospital_mortality_rate
FROM all_icu_metrics
ORDER BY cohort_label;