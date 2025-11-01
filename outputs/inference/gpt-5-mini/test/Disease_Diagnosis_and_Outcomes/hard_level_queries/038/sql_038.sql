WITH
patients_adm AS (
  -- Base admissions joined to patient demographics
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod,
    -- LOS in days (integer). Null if dischtime is null.
    CASE WHEN a.dischtime IS NOT NULL THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) ELSE NULL END AS los_days,
    DATE(a.admittime) AS admit_date
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  -- We keep all admissions here and will filter to male & age 74-84 later
),

diag_text AS (
  -- Diagnoses with description text for pattern matching
  SELECT
    d.hadm_id,
    LOWER(coalesce(dc.long_title, '')) AS long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dc
    ON d.icd_code = dc.icd_code
    AND SAFE_CAST(d.icd_version AS STRING) = SAFE_CAST(dc.icd_version AS STRING)
  GROUP BY d.hadm_id, long_title
),

hadm_flags AS (
  -- Per-hadm flags: AKI, ARDS, and a set of comorbidity group flags used to build a comorbidity_count
  SELECT
    h.hadm_id,
    MAX(CASE WHEN dt.long_title LIKE '%acute kidney%' OR dt.long_title LIKE '%acute renal%' THEN 1 ELSE 0 END) AS is_aki,
    MAX(CASE WHEN dt.long_title LIKE '%acute respiratory distress%' OR dt.long_title LIKE '%ards%' THEN 1 ELSE 0 END) AS is_ards,
    -- Comorbidity groups (binary): patterns chosen as a Charlson-like surrogate
    MAX(CASE WHEN dt.long_title LIKE '%congestive heart failure%' OR dt.long_title LIKE '%heart failure%' THEN 1 ELSE 0 END) AS c_chf,
    MAX(CASE WHEN dt.long_title LIKE '%myocardial infarction%' OR dt.long_title LIKE '%acute myocardial%' OR dt.long_title LIKE '%heart attack%' THEN 1 ELSE 0 END) AS c_mi,
    MAX(CASE WHEN dt.long_title LIKE '%cerebrovascular%' OR dt.long_title LIKE '%stroke%' OR dt.long_title LIKE '%hemiplegia%' THEN 1 ELSE 0 END) AS c_cerebro,
    MAX(CASE WHEN dt.long_title LIKE '%dementia%' THEN 1 ELSE 0 END) AS c_dementia,
    MAX(CASE WHEN dt.long_title LIKE '%chronic obstructive%' OR dt.long_title LIKE '%emphysema%' OR dt.long_title LIKE '%copd%' THEN 1 ELSE 0 END) AS c_copd,
    MAX(CASE WHEN dt.long_title LIKE '%diabetes%' THEN 1 ELSE 0 END) AS c_diabetes,
    MAX(CASE WHEN dt.long_title LIKE '%chronic kidney%' OR dt.long_title LIKE '%chronic renal%' OR dt.long_title LIKE '%renal failure, chronic%' THEN 1 ELSE 0 END) AS c_ckd,
    MAX(CASE WHEN dt.long_title LIKE '%liver%' OR dt.long_title LIKE '%cirrhosis%' OR dt.long_title LIKE '%chronic hepatitis%' THEN 1 ELSE 0 END) AS c_liver,
    MAX(CASE WHEN dt.long_title LIKE '%malign%' OR dt.long_title LIKE '%neoplasm%' OR dt.long_title LIKE '%cancer%' THEN 1 ELSE 0 END) AS c_cancer,
    MAX(CASE WHEN dt.long_title LIKE '%metastatic%' THEN 1 ELSE 0 END) AS c_metastatic,
    MAX(CASE WHEN dt.long_title LIKE '%hiv%' OR dt.long_title LIKE '%aids%' THEN 1 ELSE 0 END) AS c_aids
  FROM (
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  ) h
  LEFT JOIN diag_text dt
    ON h.hadm_id = dt.hadm_id
  GROUP BY h.hadm_id
),

hadm_comorbidity AS (
  -- Compute comorbidity_count as sum of the binary comorbidity group flags per admission
  SELECT
    hf.hadm_id,
    hf.is_aki,
    hf.is_ards,
    (hf.c_chf + hf.c_mi + hf.c_cerebro + hf.c_dementia + hf.c_copd + hf.c_diabetes + hf.c_ckd + hf.c_liver + hf.c_cancer + hf.c_metastatic + hf.c_aids) AS comorbidity_count
  FROM hadm_flags hf
),

male_74_84 AS (
  -- Filter to male inpatients aged 74-84 (by anchor_age)
  SELECT
    pa.*,
    COALESCE(hc.comorbidity_count, 0) AS comorbidity_count,
    COALESCE(hc.is_aki, 0) AS is_aki,
    COALESCE(hc.is_ards, 0) AS is_ards,
    -- death within 30 days of admission (patients.dod is a DATE)
    CASE
      WHEN pa.dod IS NOT NULL
       AND pa.dod BETWEEN DATE(pa.admit_date) AND DATE_ADD(DATE(pa.admit_date), INTERVAL 30 DAY)
      THEN 1 ELSE 0
    END AS death_within_30d
  FROM patients_adm pa
  LEFT JOIN hadm_comorbidity hc
    USING (hadm_id)
  WHERE pa.gender = 'M'
    AND pa.anchor_age BETWEEN 74 AND 84
),

-- Aggregates for the general male 74-84 cohort
general_stats AS (
  SELECT
    COUNT(*) AS n_admissions,
    -- comorbidity_count quartiles: returns array [min, Q1, median, Q3, max]
    (APPROX_QUANTILES(comorbidity_count, 4))[OFFSET(1)] AS comorb_q1,
    (APPROX_QUANTILES(comorbidity_count, 4))[OFFSET(2)] AS comorb_median,
    (APPROX_QUANTILES(comorbidity_count, 4))[OFFSET(3)] AS comorb_q3,
    -- 30-day mortality rate
    SUM(death_within_30d) AS deaths_30d,
    ROUND(100.0 * SAFE_DIVIDE(SUM(death_within_30d), COUNT(*)), 2) AS pct_mortality_30d,
    -- ARDS rate
    SUM(is_ards) AS n_ards,
    ROUND(100.0 * SAFE_DIVIDE(SUM(is_ards), COUNT(*)), 2) AS pct_ards,
    -- survivor LOS median among survivors
    (APPROX_QUANTILES(los_days, 4))[OFFSET(2)] AS survivor_los_median_days -- will include NULLs so survivors filter below
  FROM male_74_84
  WHERE 1=1
),

-- Aggregates for the AKI cohort (subset of male_74_84 with is_aki=1)
aki_stats AS (
  SELECT
    COUNT(*) AS n_admissions,
    (APPROX_QUANTILES(comorbidity_count, 4))[OFFSET(1)] AS comorb_q1,
    (APPROX_QUANTILES(comorbidity_count, 4))[OFFSET(2)] AS comorb_median,
    (APPROX_QUANTILES(comorbidity_count, 4))[OFFSET(3)] AS comorb_q3,
    SUM(death_within_30d) AS deaths_30d,
    ROUND(100.0 * SAFE_DIVIDE(SUM(death_within_30d), COUNT(*)), 2) AS pct_mortality_30d,
    SUM(is_ards) AS n_ards,
    ROUND(100.0 * SAFE_DIVIDE(SUM(is_ards), COUNT(*)), 2) AS pct_ards,
    -- survivor LOS among survivors (exclude rows with hospital_expire_flag = 1 or NULL)
    (APPROX_QUANTILES(los_days, 4))[OFFSET(2)] AS survivor_los_median_days
  FROM male_74_84
  WHERE is_aki = 1
),

-- For risk percentile: compute distribution of comorbidity_count in the general cohort
general_comorb_dist AS (
  SELECT
    comorbidity_count,
    COUNT(*) AS cnt
  FROM male_74_84
  GROUP BY comorbidity_count
),

general_comorb_cume AS (
  SELECT
    comorbidity_count,
    cnt,
    SUM(cnt) OVER (ORDER BY comorbidity_count ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_cnt,
    SUM(cnt) OVER () AS total_cnt
  FROM general_comorb_dist
),

-- Each AKI admission's percentile in the general distribution (proportion with comorbidity_count <= value)
aki_percentiles AS (
  SELECT
    a.hadm_id,
    a.comorbidity_count,
    COALESCE(gc.cum_cnt / NULLIF(gc.total_cnt,0), 0) AS percentile  -- between 0 and 1
  FROM male_74_84 a
  LEFT JOIN general_comorb_cume gc
    ON a.comorbidity_count = gc.comorbidity_count
  WHERE a.is_aki = 1
),

-- Summary of AKI percentiles (median percentile)
aki_percentile_summary AS (
  SELECT
    COUNT(*) AS n_aki,
    100.0 * (APPROX_QUANTILES(percentile, 4))[OFFSET(2)] AS median_percentile_of_aki_vs_general -- as percent
  FROM aki_percentiles
)

-- Final select: present AKI and General summary and risk percentile
SELECT
  'AKI_cohort_male_age_74_84' AS cohort,
  a.n_admissions AS n_admissions,
  a.comorb_median AS comorbidity_median,
  CONCAT(a.comorb_q1, ' - ', a.comorb_q3) AS comorbidity_IQR,
  a.pct_mortality_30d AS pct_30d_mortality,
  a.pct_ards AS pct_ards,
  a.survivor_los_median_days AS survivor_median_los_days,
  p.median_percentile_of_aki_vs_general AS median_risk_percentile_vs_general
FROM aki_stats a
CROSS JOIN aki_percentile_summary p

UNION ALL

SELECT
  'General_male_age_74_84' AS cohort,
  g.n_admissions AS n_admissions,
  g.comorb_median AS comorbidity_median,
  CONCAT(g.comorb_q1, ' - ', g.comorb_q3) AS comorbidity_IQR,
  g.pct_mortality_30d AS pct_30d_mortality,
  g.pct_ards AS pct_ards,
  g.survivor_los_median_days AS survivor_median_los_days,
  NULL AS median_risk_percentile_vs_general
FROM general_stats g;