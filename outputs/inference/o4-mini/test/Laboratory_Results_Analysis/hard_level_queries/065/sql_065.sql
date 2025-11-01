WITH
-- 1. Identify admissions of women 65-75
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),
-- 2. Lower GI bleed cohort via ICD 
bleed_icd AS (
  SELECT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%lower gastrointestinal%' 
    AND (
      LOWER(dd.long_title) LIKE '%hemorrhage%' 
      OR LOWER(dd.long_title) LIKE '%bleed%'
    )
  GROUP BY
    d.hadm_id
),
-- 3. Lab instability scores per admission
lab_scores AS (
  SELECT
    le.hadm_id,
    COUNTIF(
      le.valuenum < le.ref_range_lower
      OR le.valuenum > le.ref_range_upper
    ) AS instab_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE
    le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
  GROUP BY
    le.hadm_id
),
-- 4a. Metrics for bleed cohort
bleed_metrics AS (
  SELECT
    'lower_gi_bleed' AS cohort,
    COUNT(DISTINCT b.hadm_id) AS n_admissions,
    -- 25th percentile lab-instability score
    APPROX_QUANTILES(ls.instab_count, 100)[OFFSET(25)] AS instab_25p,
    -- mean daily lab‐instability frequency = instab_count / LOS
    AVG(ls.instab_count / NULLIF(b.los_days, 0)) AS mean_instab_per_day,
    AVG(b.los_days) AS mean_los_days,
    AVG(b.hospital_expire_flag) AS mortality_rate
  FROM
    base b
    JOIN bleed_icd bi 
      ON b.hadm_id = bi.hadm_id
    LEFT JOIN lab_scores ls 
      ON b.hadm_id = ls.hadm_id
),
-- 4b. Metrics for general cohort (same age/gender)
general_metrics AS (
  SELECT
    'general_inpatients' AS cohort,
    COUNT(DISTINCT b.hadm_id) AS n_admissions,
    APPROX_QUANTILES(ls.instab_count, 100)[OFFSET(25)] AS instab_25p,
    AVG(ls.instab_count / NULLIF(b.los_days, 0)) AS mean_instab_per_day,
    AVG(b.los_days) AS mean_los_days,
    AVG(b.hospital_expire_flag) AS mortality_rate
  FROM
    base b
    LEFT JOIN lab_scores ls 
      ON b.hadm_id = ls.hadm_id
)
-- 5. Combine results
SELECT * FROM bleed_metrics
UNION ALL
SELECT * FROM general_metrics;