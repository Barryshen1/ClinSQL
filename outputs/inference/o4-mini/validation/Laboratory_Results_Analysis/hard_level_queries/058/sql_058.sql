WITH
-- 1. Identify ACS admissions in female patients age 40-50
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      LOWER(dd.long_title) LIKE '%acute coronary%'
      OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
    )
),
-- 2. Compute first-48h lab events for any admission
labs_48 AS (
  SELECT
    le.hadm_id,
    le.labevent_id,
    le.itemid,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    le.flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      USING (hadm_id)
  WHERE
    le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),
-- 3. Per-admission instability score: count distinct itemids outside ref range
instability_scores AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT itemid) AS instab_score,
    COUNT(*) AS total_labs,
    SAFE_DIVIDE(
      SUM(CASE WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1 ELSE 0 END),
      COUNT(*)
    ) AS instab_rate,
    SAFE_DIVIDE(
      SUM(CASE WHEN flag IS NOT NULL THEN 1 ELSE 0 END),
      COUNT(*)
    ) AS critical_rate
  FROM labs_48
  WHERE valuenum IS NOT NULL
    AND ref_range_lower IS NOT NULL
    AND ref_range_upper IS NOT NULL
  GROUP BY hadm_id
),
-- 4. Restrict instability scores to the ACS cohort (not strictly needed downstream)
acs_scores AS (
  SELECT
    s.*
  FROM instability_scores AS s
  JOIN acs_admissions AS a
    USING (hadm_id)
),
-- 5. Compute the 90th percentile of the instability score in the ACS cohort
p90 AS (
  SELECT
    CAST(q_val AS INT64) AS threshold_score
  FROM (
    SELECT
      APPROX_QUANTILES(instab_score, 100) AS q_array
    FROM acs_scores
  ), UNNEST(q_array) AS q_val WITH OFFSET pos
  WHERE pos = 90
),
-- 6. Define high-instability ACS subcohort
high_acs AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    s.instab_score,
    s.critical_rate
  FROM acs_admissions AS a
  JOIN instability_scores AS s
    USING (hadm_id)
  CROSS JOIN p90
  WHERE s.instab_score >= p90.threshold_score
),
-- 7. Metrics for the high-instability ACS subcohort
metrics_high_acs AS (
  SELECT
    'High-instability ACS (>=90th pct)' AS cohort,
    AVG(hospital_expire_flag)    AS mortality_rate,
    AVG(los_days)                AS mean_los_days,
    AVG(critical_rate)           AS mean_critical_lab_rate
  FROM high_acs
),
-- 8. Metrics for general inpatients exceeding the same threshold
general_above_p90 AS (
  SELECT
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    s.critical_rate
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN instability_scores AS s
      USING (hadm_id)
    CROSS JOIN p90
  WHERE s.instab_score >= p90.threshold_score
),
metrics_general AS (
  SELECT
    'General inpatients (>=90th pct)' AS cohort,
    AVG(hospital_expire_flag)    AS mortality_rate,
    AVG(los_days)                AS mean_los_days,
    AVG(critical_rate)           AS mean_critical_lab_rate
  FROM general_above_p90
)
-- 9. Combine results
SELECT * FROM metrics_high_acs
UNION ALL
SELECT * FROM metrics_general;