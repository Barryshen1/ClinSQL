WITH
-- 1. Admissions for male patients age 52-62
male_age_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

-- 2. Identify admissions "admitted with asthma" by primary diagnosis (seq_num = 1) matching diagnoses text
asthma_primary_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      LOWER(COALESCE(dicd.long_title, '')) LIKE '%asthma%'
      -- fallback on common asthma ICD prefixes (ICD10 J45*, ICD9 493*)
      OR d.icd_code LIKE 'J45%'
      OR d.icd_code LIKE '493%'
    )
),

-- 3. Cohort: male, age 52-62, primary-admission for asthma
asthma_cohort AS (
  SELECT
    m.*
  FROM
    male_age_admissions m
    JOIN asthma_primary_admissions a
      ON m.hadm_id = a.hadm_id
),

-- 4. Lab events in first 72 hours for admissions of interest (we will later reuse similar logic for the age-matched comparison cohort)
labs_72h AS (
  -- Combine labs for ALL male age 52-62 admissions (we will restrict to asthma or overall later)
  SELECT
    ma.hadm_id,
    le.labevent_id,
    le.subject_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    le.value,
    le.valueuom,
    le.ref_range_lower,
    le.ref_range_upper,
    le.flag
  FROM
    male_age_admissions ma
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON le.hadm_id = ma.hadm_id
  WHERE
    -- ensure lab has a charttime and occurs within 72 hours of admission
    le.charttime IS NOT NULL
    AND le.charttime >= ma.admittime
    AND le.charttime <= TIMESTAMP_ADD(ma.admittime, INTERVAL 72 HOUR)
),

-- 5. Flag abnormal and critical for each lab row
labs_72h_flagged AS (
  SELECT
    h.hadm_id,
    h.labevent_id,
    h.subject_id,
    h.itemid,
    h.charttime,
    h.valuenum,
    h.ref_range_lower,
    h.ref_range_upper,
    h.flag,
    -- abnormal if numeric value outside reference range when available OR flag indicates abnormal/high/low
    (
      (h.valuenum IS NOT NULL
        AND (
          (h.ref_range_lower IS NOT NULL AND h.valuenum < h.ref_range_lower)
          OR (h.ref_range_upper IS NOT NULL AND h.valuenum > h.ref_range_upper)
        )
      )
      OR (LOWER(COALESCE(h.flag, '')) LIKE '%abnorm%')
      OR (LOWER(COALESCE(h.flag, '')) LIKE '%high%')
      OR (LOWER(COALESCE(h.flag, '')) LIKE '%low%')
    ) AS is_abnormal,
    -- critical: flag mentions 'crit' OR large deviation when refs available (50% below lower or 50% above upper)
    (
      (LOWER(COALESCE(h.flag, '')) LIKE '%crit%')
      OR (
        h.valuenum IS NOT NULL
        AND h.ref_range_lower IS NOT NULL
        AND h.ref_range_upper IS NOT NULL
        AND (
          h.valuenum < 0.5 * h.ref_range_lower
          OR h.valuenum > 1.5 * h.ref_range_upper
        )
      )
    ) AS is_critical
  FROM
    labs_72h h
),

-- 6. Aggregate per admission: instability_score (abnormal count) and critical_count within 72h
admission_lab_scores AS (
  SELECT
    ma.hadm_id,
    ma.subject_id,
    ma.admittime,
    ma.dischtime,
    ma.hospital_expire_flag,
    COALESCE(SUM(IF(lf.is_abnormal, 1, 0)), 0) AS instability_score,
    COALESCE(SUM(IF(lf.is_critical, 1, 0)), 0) AS critical_count,
    COALESCE(COUNT(lf.labevent_id), 0) AS total_lab_events_72h
  FROM
    male_age_admissions ma
    LEFT JOIN labs_72h_flagged lf
      ON ma.hadm_id = lf.hadm_id
  GROUP BY
    ma.hadm_id, ma.subject_id, ma.admittime, ma.dischtime, ma.hospital_expire_flag
),

-- 7. Restrict admission_lab_scores to the asthma cohort for percentile calculation
asthma_admission_scores AS (
  SELECT
    als.*
  FROM
    admission_lab_scores als
    JOIN asthma_cohort ac
      USING (hadm_id)
),

-- 8. Compute the 90th percentile instability score among the asthma cohort
asthma_p90 AS (
  SELECT
    -- APPROX_QUANTILES with 100 buckets, offset 90 gives the 90th percentile approx
    (APPROX_QUANTILES(instability_score, 100))[OFFSET(90)] AS p90_instability_score
  FROM
    asthma_admission_scores
),

-- 9. Identify top-decile asthma admissions (instability_score >= 90th percentile)
asthma_top_decile AS (
  SELECT
    s.*
  FROM
    asthma_admission_scores s,
    asthma_p90 p
  WHERE
    s.instability_score >= p.p90_instability_score
),

-- 10. Metrics for asthma top decile
asthma_top_metrics AS (
  SELECT
    'Asthma_top_decile' AS group_name,
    COUNT(*) AS n_admissions,
    -- mortality rate
    SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)) AS mortality_rate,
    -- mean LOS in days (use minutes to compute fractional days)
    AVG(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, MINUTE), 1440.0)) AS mean_los_days,
    -- average number of critical lab events in the 72h window
    AVG(critical_count) AS avg_critical_events,
    -- mean instability score
    AVG(instability_score) AS mean_instability_score
  FROM
    asthma_top_decile
),

-- 11. Metrics for all age-matched males (comparison group)
age_matched_metrics AS (
  SELECT
    'Age_matched_males_52_62' AS group_name,
    COUNT(*) AS n_admissions,
    SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)) AS mortality_rate,
    AVG(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, MINUTE), 1440.0)) AS mean_los_days,
    AVG(critical_count) AS avg_critical_events,
    AVG(instability_score) AS mean_instability_score
  FROM
    admission_lab_scores
)

-- Final output: report the 90th percentile and details for the two groups
SELECT
  'asthma_90th_percentile_instability_score' AS metric,
  CAST(p.p90_instability_score AS STRING) AS value
FROM
  asthma_p90 p

UNION ALL

SELECT
  'group_summary',
  TO_JSON_STRING(t)
FROM (
  SELECT * FROM asthma_top_metrics
  UNION ALL
  SELECT * FROM age_matched_metrics
) t
ORDER BY metric DESC;