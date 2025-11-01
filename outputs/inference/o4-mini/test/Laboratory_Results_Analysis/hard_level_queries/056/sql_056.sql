WITH
-- 1. Base inpatient admissions for females 55-65
inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)/86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
),

-- 2. Identify admissions with an asthma exacerbation diagnosis
asthma_adms AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%asthma%'
),

-- 3. Compute instability score = count out-of-range lab events in first 48h
lab_instability AS (
  SELECT
    ip.hadm_id,
    COUNTIF(
      le.valuenum IS NOT NULL
      AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    ) AS instability_score
  FROM
    inpatients ip
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ip.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN ip.admittime
      AND TIMESTAMP_ADD(ip.admittime, INTERVAL 48 HOUR)
  GROUP BY
    ip.hadm_id
),

-- 4. Combine metrics for the asthma cohort
asthma_metrics AS (
  SELECT
    ip.hadm_id,
    ip.los_days,
    ip.hospital_expire_flag AS mortality,
    li.instability_score,
    SAFE_DIVIDE(li.instability_score, 2.0) AS critical_lab_rate
  FROM
    inpatients ip
    JOIN asthma_adms aa
      ON ip.hadm_id = aa.hadm_id
    LEFT JOIN lab_instability li
      ON ip.hadm_id = li.hadm_id
),

-- 5. Compute the 95th percentile of instability_score
percentile_95 AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95
  FROM
    asthma_metrics
),

-- 6. Top‐tier asthma admissions: instability_score ≥ 95th percentile
top_asthma AS (
  SELECT
    am.*
  FROM
    asthma_metrics am,
    percentile_95 p
  WHERE
    am.instability_score >= p.p95
),

-- 7. Aggregate metrics for the top tier
top_asthma_summary AS (
  SELECT
    'Top 5% asthma' AS cohort,
    AVG(los_days)            AS avg_los_days,
    AVG(mortality)           AS mortality_rate,
    AVG(critical_lab_rate)   AS avg_critical_lab_rate_per_day
  FROM
    top_asthma
),

-- 8. Aggregate metrics for the general female 55-65 inpatient population
general_summary AS (
  SELECT
    'General female 55-65' AS cohort,
    AVG(ip.los_days)                                        AS avg_los_days,
    AVG(ip.hospital_expire_flag)                            AS mortality_rate,
    AVG(SAFE_DIVIDE(li.instability_score, 2.0))             AS avg_critical_lab_rate_per_day
  FROM
    inpatients ip
    LEFT JOIN lab_instability li
      ON ip.hadm_id = li.hadm_id
)

-- 9. Combine both summaries
SELECT * FROM top_asthma_summary
UNION ALL
SELECT * FROM general_summary;