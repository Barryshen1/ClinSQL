WITH
-- 1) Cohort: male patients age 60-70 with primary diagnosis containing "pneumonia"
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
      ON d.icd_code = diag.icd_code
      AND d.icd_version = diag.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND d.seq_num = 1                           -- primary diagnosis
    AND LOWER(diag.long_title) LIKE '%pneumonia%'
),

-- 2) For each admission and lab item, compute absolute changes between consecutive labs within first 72 hours
lab_deltas AS (
  SELECT
    le.hadm_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    LAG(le.valuenum) OVER (PARTITION BY le.hadm_id, le.itemid ORDER BY le.charttime) AS prev_valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN cohort_admissions ca
      ON le.hadm_id = ca.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 72 HOUR)
),

-- 3) Sum of absolute differences per admission => instability score
instability_scores AS (
  SELECT
    hadm_id,
    COALESCE(SUM(ABS(valuenum - prev_valuenum)), 0) AS instability_score
  FROM lab_deltas
  WHERE prev_valuenum IS NOT NULL
  GROUP BY hadm_id
),

-- 4) Ensure admissions with no computed deltas are present (score = 0)
cohort_instability AS (
  SELECT
    ca.hadm_id,
    COALESCE(iscores.instability_score, 0) AS instability_score
  FROM
    cohort_admissions ca
    LEFT JOIN instability_scores iscores
      ON ca.hadm_id = iscores.hadm_id
),

-- 5) ICU stay counts per hadm (for critical-event proxy)
icu_counts_per_hadm AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT stay_id) AS icu_stay_count
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

-- 6) Cohort-level ICU counts (join to cohort admissions, treat missing as 0)
cohort_icu AS (
  SELECT
    ca.hadm_id,
    COALESCE(icu.icu_stay_count, 0) AS icu_stay_count
  FROM
    cohort_admissions ca
    LEFT JOIN icu_counts_per_hadm icu
      ON ca.hadm_id = icu.hadm_id
),

-- 7) All-admissions ICU counts for comparison (include all hospital admissions)
all_admissions_icu AS (
  SELECT
    a.hadm_id,
    COALESCE(icu.icu_stay_count, 0) AS icu_stay_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN icu_counts_per_hadm icu
      ON a.hadm_id = icu.hadm_id
),

-- 8) Cohort LOS & mortality calculations (exclude missing datetimes)
cohort_los_mort AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
    hospital_expire_flag
  FROM
    cohort_admissions
  WHERE
    admittime IS NOT NULL
    AND dischtime IS NOT NULL
)

-- Final aggregation: produce requested metrics
SELECT
  -- Cohort size
  (SELECT COUNT(1) FROM cohort_admissions) AS cohort_n,
  -- 75th percentile of the 72-hour lab instability score
  (SELECT
     -- APPROX_QUANTILES returns an array of quantiles; 100 buckets -> index 75 is the 75th percentile
     (APPROX_QUANTILES(instability_score, 100))[OFFSET(75)]
   FROM cohort_instability) AS instability_score_75th,
  -- Mean ICU stays per admission in cohort (critical-event frequency proxy)
  (SELECT AVG(icu_stay_count) FROM cohort_icu) AS cohort_mean_icu_events_per_admission,
  -- Mean ICU stays per admission for all hospital admissions (for comparison)
  (SELECT AVG(icu_stay_count) FROM all_admissions_icu) AS all_inpatients_mean_icu_events_per_admission,
  -- Cohort LOS: mean and median (median approximated)
  (SELECT AVG(los_days) FROM cohort_los_mort) AS cohort_mean_los_days,
  (SELECT (APPROX_QUANTILES(los_days, 100))[OFFSET(50)] FROM cohort_los_mort) AS cohort_median_los_days,
  -- Cohort hospital mortality (proportion with hospital_expire_flag = 1)
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM cohort_los_mort) AS cohort_hospital_mortality_rate
;