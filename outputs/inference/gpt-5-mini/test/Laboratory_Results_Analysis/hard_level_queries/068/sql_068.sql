WITH
-- 1) admissions with septic shock for female patients aged 89-99 that have an ICU stay
septic_shock_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.hadm_id = i.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
      ON dx.icd_code = dic.icd_code
      AND dx.icd_version = dic.icd_version
  WHERE
    LOWER(dic.long_title) LIKE '%septic shock%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
),

-- 2) median heart rate per ICU stay within first 48 hours of ICU intime
hr_medians AS (
  SELECT
    ce.stay_id,
    ce.hadm_id,
    ce.subject_id,
    -- approximate median
    APPROX_QUANTILES(ce.valuenum, 2)[OFFSET(1)] AS hr_median
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    JOIN septic_shock_adms s
      ON ce.stay_id = s.stay_id
         AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  WHERE
    ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%heart rate%'
  GROUP BY
    ce.stay_id, ce.hadm_id, ce.subject_id
),

-- 3) median systolic BP per ICU stay within first 48 hours of ICU intime
sbp_medians AS (
  SELECT
    ce.stay_id,
    ce.hadm_id,
    ce.subject_id,
    APPROX_QUANTILES(ce.valuenum, 2)[OFFSET(1)] AS sbp_median
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    JOIN septic_shock_adms s
      ON ce.stay_id = s.stay_id
         AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  WHERE
    ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%systolic%'
  GROUP BY
    ce.stay_id, ce.hadm_id, ce.subject_id
),

-- 4) instability score per stay where both medians are available
instability_per_stay AS (
  SELECT
    h.stay_id,
    h.hadm_id,
    h.subject_id,
    h.hr_median,
    s.sbp_median,
    SAFE_DIVIDE(h.hr_median, s.sbp_median) AS instability_score
  FROM hr_medians h
  JOIN sbp_medians s
    ON h.stay_id = s.stay_id
),

-- 5) cohort-level instability quartiles (Q1, median, Q3) and IQR
instability_stats AS (
  SELECT
    (APPROX_QUANTILES(instability_score, 4))[OFFSET(1)] AS instability_q1,
    (APPROX_QUANTILES(instability_score, 4))[OFFSET(2)] AS instability_median,
    (APPROX_QUANTILES(instability_score, 4))[OFFSET(3)] AS instability_q3
  FROM instability_per_stay
),

-- 6) cohort counts (for denominators) and LOS/mortality per admission
cohort_adm_stats AS (
  SELECT
    s.hadm_id,
    s.subject_id,
    s.admittime,
    s.dischtime,
    s.hospital_expire_flag,
    SAFE_DIVIDE(TIMESTAMP_DIFF(s.dischtime, s.admittime, MINUTE), 60*24) AS los_days
  FROM septic_shock_adms s
),

-- 7) cohort-level LOS quartiles and median and mortality
cohort_los_mort AS (
  SELECT
    (APPROX_QUANTILES(los_days, 4))[OFFSET(1)] AS los_q1_days,
    (APPROX_QUANTILES(los_days, 4))[OFFSET(2)] AS los_median_days,
    (APPROX_QUANTILES(los_days, 4))[OFFSET(3)] AS los_q3_days,
    ((APPROX_QUANTILES(los_days, 4))[OFFSET(3)] - (APPROX_QUANTILES(los_days, 4))[OFFSET(1)]) AS los_iqr_days,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(1)) AS mortality_rate
  FROM cohort_adm_stats
),

-- 8) cohort abnormal labs within first 48 hours of hospital admission:
cohort_abnormal_labs AS (
  SELECT
    COUNT(DISTINCT l.hadm_id) AS num_hadm_with_abn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN septic_shock_adms s
      ON l.hadm_id = s.hadm_id
     AND l.charttime BETWEEN s.admittime AND TIMESTAMP_ADD(s.admittime, INTERVAL 48 HOUR)
  WHERE
    l.flag IS NOT NULL
    AND TRIM(l.flag) <> ''
),

cohort_counts AS (
  SELECT COUNT(DISTINCT hadm_id) AS cohort_hadm_count FROM septic_shock_adms
),

-- 9) general inpatients abnormal labs within first 48 hours of hospital admission
general_abnormal_labs AS (
  SELECT
    COUNT(DISTINCT l.hadm_id) AS num_hadm_with_abn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.flag IS NOT NULL
    AND TRIM(l.flag) <> ''
),

gen_adm_counts AS (
  SELECT COUNT(1) AS total_admissions FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)

-- Final assemble
SELECT
  inst.instability_q1,
  inst.instability_median,
  inst.instability_q3,
  SAFE_SUBTRACT(inst.instability_q3, inst.instability_q1) AS instability_iqr,
  -- abnormal lab frequencies as percentages
  SAFE_MULTIPLY(
    SAFE_DIVIDE(cohort_abn.num_hadm_with_abn, cohort_counts.cohort_hadm_count),
    100
  ) AS cohort_abnormal_lab_pct,
  SAFE_MULTIPLY(
    SAFE_DIVIDE(gen_abn.num_hadm_with_abn, gen_adm_counts.total_admissions),
    100
  ) AS general_abnormal_lab_pct,
  -- cohort LOS and mortality
  clm.los_median_days AS cohort_median_los_days,
  clm.los_q1_days AS cohort_los_q1_days,
  clm.los_q3_days AS cohort_los_q3_days,
  clm.los_iqr_days AS cohort_los_iqr_days,
  SAFE_MULTIPLY(clm.mortality_rate, 100) AS cohort_mortality_pct,
  -- counts for transparency
  cohort_counts.cohort_hadm_count AS cohort_hadm_count,
  gen_adm_counts.total_admissions AS general_total_admissions
FROM
  instability_stats inst
  CROSS JOIN cohort_abnormal_labs cohort_abn
  CROSS JOIN cohort_counts
  CROSS JOIN general_abnormal_labs gen_abn
  CROSS JOIN gen_adm_counts
  CROSS JOIN cohort_los_mort clm
LIMIT 1;