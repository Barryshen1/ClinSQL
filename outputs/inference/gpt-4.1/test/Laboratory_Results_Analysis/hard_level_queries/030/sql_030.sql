WITH asthma_icd_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code LIKE '493%')
    OR (icd_version = 10 AND icd_code LIKE 'J45%')
),
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN asthma_icd_codes icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
),
-- Step 2: Lab instability score in first 48h for cohort
cohort_lab_events AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.itemid,
    l.valuenum,
    l.valueuom,
    l.flag,
    l.ref_range_lower,
    l.ref_range_upper,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cohort_admissions a
    ON l.hadm_id = a.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),
cohort_lab_instability AS (
  SELECT
    subject_id,
    hadm_id,
    COUNTIF(
      -- Use flag if present, else compare valuenum to ref ranges
      (flag IS NOT NULL AND LOWER(flag) IN ('abnormal', 'high', 'low'))
      OR
      (flag IS NULL AND valuenum IS NOT NULL AND (
        (ref_range_lower IS NOT NULL AND valuenum < ref_range_lower)
        OR
        (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)
      ))
    ) AS lab_instability_score
  FROM cohort_lab_events
  GROUP BY subject_id, hadm_id
),
-- Step 3: LOS and mortality for cohort
cohort_summary AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    IFNULL(cli.lab_instability_score, 0) AS lab_instability_score,
    TIMESTAMP_DIFF(ca.dischtime, ca.admittime, DAY) AS los_days
  FROM cohort_admissions ca
  LEFT JOIN cohort_lab_instability cli
    ON ca.subject_id = cli.subject_id AND ca.hadm_id = cli.hadm_id
),
-- Step 4: All inpatients lab instability score in first 48h
all_lab_events AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.itemid,
    l.valuenum,
    l.valueuom,
    l.flag,
    l.ref_range_lower,
    l.ref_range_upper,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),
all_lab_instability AS (
  SELECT
    subject_id,
    hadm_id,
    COUNTIF(
      (flag IS NOT NULL AND LOWER(flag) IN ('abnormal', 'high', 'low'))
      OR
      (flag IS NULL AND valuenum IS NOT NULL AND (
        (ref_range_lower IS NOT NULL AND valuenum < ref_range_lower)
        OR
        (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)
      ))
    ) AS lab_instability_score
  FROM all_lab_events
  GROUP BY subject_id, hadm_id
),
all_admissions_summary AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    IFNULL(ali.lab_instability_score, 0) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN all_lab_instability ali
    ON a.subject_id = ali.subject_id AND a.hadm_id = ali.hadm_id
)
-- Final output: Cohort summary and comparison table
SELECT
  'Cohort Summary' AS section,
  COUNT(*) AS cohort_admissions,
  NULL AS cohort_avg_lab_instability,
  APPROX_QUANTILES(lab_instability_score, 4)[3] AS lab_instability_score_75th_percentile,
  APPROX_QUANTILES(los_days, 2)[1] AS median_los_days,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS in_hospital_mortality_percent
FROM cohort_summary

UNION ALL

SELECT
  'Lab Instability Comparison' AS section,
  NULL AS cohort_admissions,
  ROUND(AVG(CASE WHEN a.hadm_id IN (SELECT hadm_id FROM cohort_summary) THEN lab_instability_score ELSE NULL END), 2) AS cohort_avg_lab_instability,
  ROUND(AVG(lab_instability_score), 2) AS all_inpatients_avg_lab_instability,
  NULL AS median_los_days,
  NULL AS in_hospital_mortality_percent
FROM all_admissions_summary a;