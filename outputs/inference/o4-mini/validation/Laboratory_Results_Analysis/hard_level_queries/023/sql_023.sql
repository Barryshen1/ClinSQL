WITH
-- 1. Identify female AMI admissions age 90–100
ami_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id   = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
),
-- 2. Compute lab-instability score (count of abnormal flags) and critical counts, total counts in first 48h
lab_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNTIF(le.flag = 'abnormal') AS instability_score,
    COUNTIF(le.flag LIKE 'crit%') AS critical_count,
    COUNT(*) AS total_lab_count
  FROM
    ami_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.subject_id = le.subject_id
      AND a.hadm_id    = le.hadm_id
  WHERE
    TIMESTAMP_DIFF(le.charttime, a.admittime, HOUR) BETWEEN 0 AND 48
  GROUP BY
    a.subject_id,
    a.hadm_id
),
-- 3. Compute the 75th percentile of instability_score among AMI cohort
percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
  FROM
    lab_scores
),
-- 4. Define the high‐instability AMI cohort: those with score ≥ P75
high_inst_ami AS (
  SELECT
    ls.subject_id,
    ls.hadm_id,
    aa.admittime,
    aa.dischtime,
    aa.hospital_expire_flag,
    ls.instability_score,
    SAFE_DIVIDE(ls.critical_count, NULLIF(ls.total_lab_count, 0)) AS crit_rate
  FROM
    lab_scores ls
    CROSS JOIN percentiles p
    JOIN ami_admissions aa
      ON ls.subject_id = aa.subject_id
      AND ls.hadm_id    = aa.hadm_id
  WHERE
    ls.instability_score >= p.p75_score
),
-- 5. Define all inpatients age 90–100 cohort
all_age90_100 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.anchor_age BETWEEN 90 AND 100
),
-- 6. Compute critical‐lab rate for all inpatients 90–100 in first 48h
all_lab_rates AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNTIF(le.flag LIKE 'crit%') AS critical_count,
    COUNT(*) AS total_lab_count
  FROM
    all_age90_100 a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.subject_id = le.subject_id
      AND a.hadm_id    = le.hadm_id
      AND TIMESTAMP_DIFF(le.charttime, a.admittime, HOUR) BETWEEN 0 AND 48
  GROUP BY
    a.subject_id,
    a.hadm_id
),
all_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    SAFE_DIVIDE(alr.critical_count, NULLIF(alr.total_lab_count, 0)) AS crit_rate
  FROM
    all_age90_100 a
    LEFT JOIN all_lab_rates alr
      ON a.subject_id = alr.subject_id
      AND a.hadm_id    = alr.hadm_id
)
-- 7. Summarize metrics for both cohorts
SELECT
  'High-instability AMI (≥P75)' AS cohort,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS INT64)), 2) AS in_hospital_mortality_pct,
  ROUND(AVG(DATE_DIFF(dischtime, admittime, DAY)), 2) AS mean_los_days,
  ROUND(AVG(crit_rate) * 100, 2) AS mean_critical_lab_rate_pct
FROM
  high_inst_ami

UNION ALL

SELECT
  'All inpatients age 90–100' AS cohort,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS INT64)), 2) AS in_hospital_mortality_pct,
  ROUND(AVG(DATE_DIFF(dischtime, admittime, DAY)), 2) AS mean_los_days,
  ROUND(AVG(crit_rate) * 100, 2) AS mean_critical_lab_rate_pct
FROM
  all_cohort;