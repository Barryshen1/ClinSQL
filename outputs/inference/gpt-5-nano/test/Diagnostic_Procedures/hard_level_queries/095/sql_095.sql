with pe_cohort as (
  select
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  from `physionet-data.mimiciv_3_1_icu.icustays` as s
  join `physionet-data.mimiciv_3_1_hosp.patients` as p
    on s.subject_id = p.subject_id
  join `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` as diags
    on diags.subject_id = s.subject_id and diags.hadm_id = s.hadm_id
  join `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` as dd
    on diags.icd_code = dd.icd_code and diags.icd_version = dd.icd_version
  where
    p.gender = 'M'
    and p.anchor_age between 79 and 89
    and lower(dd.long_title) like '%pulmonary embolism%'
),

-- 2) Diagnostic utilization score: count of lab tests in first 24h of ICU stay
scores as (
  select
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    count(le.itemid) AS diagnostic_utilization_score
  from pe_cohort pc
  left join `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = pc.subject_id
   AND le.hadm_id = pc.hadm_id
   AND le.charttime >= pc.intime
   AND le.charttime < TIMESTAMP_ADD(pc.intime, INTERVAL 24 HOUR)
  GROUP BY pc.subject_id, pc.hadm_id, pc.stay_id
),

-- 3) 75th percentile of the diagnostic utilization score in the PE cohort
percentile_75 AS (
  SELECT
    quantiles[OFFSET(75)] AS percentile_75
  FROM (
    SELECT APPROX_QUANTILES(diagnostic_utilization_score, 100) AS quantiles
    FROM scores
  )
),

-- 4) PE cohort metrics: approximate median ICU LOS and in-hospital mortality
pe_metrics AS (
  -- approximate median ICU LOS for PE cohort using 100-quantile approach
  SELECT quantiles[OFFSET(50)] AS pe_median_los
  FROM (
    SELECT APPROX_QUANTILES(los, 100) AS quantiles
    FROM pe_cohort pc
  )
),
pe_mortality AS (
  -- in-hospital mortality for PE cohort
  SELECT AVG(CASE
               WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1
               ELSE 0
             END) AS pe_inhospital_mortality
  FROM pe_cohort pc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pc.hadm_id = a.hadm_id
),

-- 5) General ICU population metrics (all icustays)
general_metrics AS (
  -- approximate median ICU LOS for all ICU stays
  SELECT quantiles[OFFSET(50)] AS general_median_los
  FROM (
    SELECT APPROX_QUANTILES(s.los, 100) AS quantiles
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  )
),
general_mortality AS (
  -- in-hospital mortality for all ICU admissions
  SELECT AVG(
           CASE
             WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1
             ELSE 0
           END
         ) AS general_inhospital_mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON s.hadm_id = a.hadm_id
)

-- 6) Combine results into a single row
SELECT
  percentile_75.percentile_75 AS percentile_75_diagnostic_utilization,
  pe_metrics.pe_median_los AS pe_median_icu_los,
  pe_mortality.pe_inhospital_mortality AS pe_inhospital_mortality_rate,
  general_metrics.general_median_los AS general_median_icu_los,
  general_mortality.general_inhospital_mortality AS general_inhospital_mortality_rate
FROM percentile_75
CROSS JOIN pe_metrics
CROSS JOIN pe_mortality
CROSS JOIN general_metrics
CROSS JOIN general_mortality;