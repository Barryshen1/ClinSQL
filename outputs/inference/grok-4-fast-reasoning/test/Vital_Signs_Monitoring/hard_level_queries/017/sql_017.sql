WITH asthma_hadms AS (
  -- Asthma cohort: qualifying admissions with asthma
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '493%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J45%')
    )
),
control_hadms AS (
  -- Control cohort: qualifying admissions WITHOUT asthma
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '493%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'J45%')
        )
    )
),
cohort_hadms AS (
  SELECT 'asthma' AS cohort, subject_id, hadm_id, anchor_age, hospital_expire_flag
  FROM asthma_hadms
  UNION ALL
  SELECT 'control' AS cohort, subject_id, hadm_id, anchor_age, hospital_expire_flag
  FROM control_hadms
),
first_stays AS (
  SELECT hadm_id, stay_id, intime, los,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort_stays AS (
  -- First ICU stay per qualifying admission, for both cohorts
  SELECT
    ch.cohort,
    ch.subject_id,
    ch.hadm_id,
    fs.stay_id,
    fs.intime,
    fs.los,
    ch.hospital_expire_flag,
    ch.anchor_age
  FROM cohort_hadms ch
  INNER JOIN first_stays fs
    ON ch.hadm_id = fs.hadm_id AND fs.rn = 1
),
rr_events AS (
  -- RR measurements in first 72h per stay
  SELECT
    cs.stay_id,
    cs.cohort,
    c.valuenum,
    cs.intime
  FROM cohort_stays cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON cs.stay_id = c.stay_id
  WHERE c.itemid IN (618, 619, 220210)  -- RR itemids
    AND c.valuenum IS NOT NULL
    AND c.charttime >= cs.intime
    AND c.charttime < TIMESTAMP_ADD(cs.intime, INTERVAL 72 HOUR)
),
per_stay_stats AS (
  -- Per-stay instability score (SD of RR) and burden (mean RR)
  SELECT
    re.stay_id,
    re.cohort,
    STDDEV(re.valuenum) AS instability_score,  -- Proxy for instability
    AVG(re.valuenum) AS score_burden  -- Mean RR as burden proxy
  FROM rr_events re
  GROUP BY re.stay_id, re.cohort
  HAVING instability_score IS NOT NULL  -- Exclude stays with no RR data
),
stay_summary AS (
  -- Join back to get LOS, mortality per stay
  SELECT
    pss.cohort,
    pss.instability_score,
    pss.score_burden,
    cs.los,
    cs.hospital_expire_flag
  FROM per_stay_stats pss
  INNER JOIN cohort_stays cs
    ON pss.stay_id = cs.stay_id
),
asthma_score_stats AS (
  -- Asthma-specific: SD and percentiles of instability score
  SELECT
    STDDEV(instability_score) AS instability_sd,
    APPROX_QUANTILES(instability_score, 20)[OFFSET(5)] AS p25,
    APPROX_QUANTILES(instability_score, 20)[OFFSET(10)] AS p50,
    APPROX_QUANTILES(instability_score, 20)[OFFSET(15)] AS p75,
    APPROX_QUANTILES(instability_score, 20)[OFFSET(19)] AS p95,
    COUNT(*) AS n_patients
  FROM stay_summary
  WHERE cohort = 'asthma'
),
comparison_stats AS (
  -- Comparisons for both cohorts: mean burden, mean/median LOS, mortality %
  SELECT
    cohort,
    AVG(score_burden) AS mean_score_burden,
    PERCENTILE_CONT(score_burden, 0.5) AS median_score_burden,
    AVG(los) AS mean_icu_los,
    PERCENTILE_CONT(los, 0.5) AS median_icu_los,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    COUNT(*) AS n_patients
  FROM stay_summary
  GROUP BY cohort
)
-- Output: Asthma score details + comparisons
SELECT 'Asthma Cohort - Instability Score' AS metric, CAST(instability_sd AS STRING) AS value FROM asthma_score_stats
UNION ALL SELECT 'Asthma Cohort - 25th Percentile', CAST(p25 AS STRING) FROM asthma_score_stats
UNION ALL SELECT 'Asthma Cohort - 50th Percentile', CAST(p50 AS STRING) FROM asthma_score_stats
UNION ALL SELECT 'Asthma Cohort - 75th Percentile', CAST(p75 AS STRING) FROM asthma_score_stats
UNION ALL SELECT 'Asthma Cohort - 95th Percentile', CAST(p95 AS STRING) FROM asthma_score_stats
UNION ALL SELECT 'Asthma Cohort - N', CAST(n_patients AS STRING) FROM asthma_score_stats
UNION ALL
SELECT
  cohort || ' - Mean Score Burden' AS metric,
  CAST(mean_score_burden AS STRING) AS value
FROM comparison_stats
UNION ALL
SELECT
  cohort || ' - Median Score Burden' AS metric,
  CAST(median_score_burden AS STRING) AS value
FROM comparison_stats
UNION ALL
SELECT
  cohort || ' - Mean ICU LOS (days)' AS metric,
  CAST(mean_icu_los AS STRING) AS value
FROM comparison_stats
UNION ALL
SELECT
  cohort || ' - Median ICU LOS (days)' AS metric,
  CAST(median_icu_los AS STRING) AS value
FROM comparison_stats
UNION ALL
SELECT
  cohort || ' - Mortality %' AS metric,
  CAST(mortality_pct AS STRING) AS value
FROM comparison_stats
UNION ALL
SELECT
  cohort || ' - N' AS metric,
  CAST(n_patients AS STRING) AS value
FROM comparison_stats
ORDER BY metric;