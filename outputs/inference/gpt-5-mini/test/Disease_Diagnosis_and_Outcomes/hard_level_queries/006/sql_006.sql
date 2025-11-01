WITH lower_gi_hadm AS (
  -- Identify hospital admissions that include a diagnosis suggestive of lower GI bleeding.
  -- We match on d_icd_diagnoses.long_title with keywords commonly used for lower-GI bleeding.
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE (
        LOWER(dd.long_title) LIKE '%lower%' AND LOWER(dd.long_title) LIKE '%gastrointestinal%'
     OR LOWER(dd.long_title) LIKE '%rectal%'
     OR LOWER(dd.long_title) LIKE '%melena%'
     OR LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%gastrointestinal haemorrhage%'
     OR LOWER(dd.long_title) LIKE '%diverticulosis%hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%bleeding from%' 
     OR LOWER(dd.long_title) LIKE '%bleeding of rectum%'
  )
),

diag_flags AS (
  -- For each admission, flag presence of major complication classes by scanning diagnoses.
  -- Use both icd_code patterns (by icd_version) and long_title text matching to be inclusive.
  SELECT
    di.hadm_id,
    MAX(CASE
          WHEN (di.icd_version = 9 AND SAFE_CAST(di.icd_code AS STRING) LIKE '584%')
            OR (di.icd_version = 10 AND SAFE_CAST(di.icd_code AS STRING) LIKE 'N17%')
            OR LOWER(dd.long_title) LIKE '%acute kidney%'
            OR LOWER(dd.long_title) LIKE '%acute renal%'
          THEN 1 ELSE 0 END) AS aki_flag,
    MAX(CASE
          WHEN (di.icd_version = 9 AND (SAFE_CAST(di.icd_code AS STRING) LIKE '9959%' OR SAFE_CAST(di.icd_code AS STRING) LIKE '038%'))
            OR (di.icd_version = 10 AND SAFE_CAST(di.icd_code AS STRING) LIKE 'A41%')
            OR LOWER(dd.long_title) LIKE '%sepsis%'
            OR LOWER(dd.long_title) LIKE '%septic%'
          THEN 1 ELSE 0 END) AS sepsis_flag,
    MAX(CASE
          WHEN (di.icd_version = 9 AND SAFE_CAST(di.icd_code AS STRING) LIKE '410%')
            OR (di.icd_version = 10 AND SAFE_CAST(di.icd_code AS STRING) LIKE 'I21%')
            OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
            OR LOWER(dd.long_title) LIKE '%acute myocardial%'
          THEN 1 ELSE 0 END) AS mi_flag,
    MAX(CASE
          WHEN (di.icd_version = 9 AND (SAFE_CAST(di.icd_code AS STRING) LIKE '433%' OR SAFE_CAST(di.icd_code AS STRING) LIKE '434%' OR SAFE_CAST(di.icd_code AS STRING) = '436'))
            OR (di.icd_version = 10 AND SAFE_CAST(di.icd_code AS STRING) LIKE 'I63%')
            OR LOWER(dd.long_title) LIKE '%stroke%'
            OR LOWER(dd.long_title) LIKE '%cerebral infarction%'
          THEN 1 ELSE 0 END) AS stroke_flag,
    MAX(CASE
          WHEN (di.icd_version = 9 AND (SAFE_CAST(di.icd_code AS STRING) LIKE '51881' OR SAFE_CAST(di.icd_code AS STRING) LIKE '51882' OR SAFE_CAST(di.icd_code AS STRING) LIKE '7855%'))
            OR (di.icd_version = 10 AND SAFE_CAST(di.icd_code AS STRING) LIKE 'J96%')
            OR LOWER(dd.long_title) LIKE '%respiratory failure%'
          THEN 1 ELSE 0 END) AS respfail_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),

cohort AS (
  -- Build the analytic cohort: female patients age 70-80 with a lower-GI-bleeding admission.
  SELECT
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    -- LOS in days (integer). If dischtime is NULL, los_days will be NULL.
    CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS INT64) AS los_days,
    COALESCE(df.aki_flag, 0) AS aki_flag,
    COALESCE(df.sepsis_flag, 0) AS sepsis_flag,
    COALESCE(df.mi_flag, 0) AS mi_flag,
    COALESCE(df.stroke_flag, 0) AS stroke_flag,
    COALESCE(df.respfail_flag, 0) AS respfail_flag,
    -- composite = sum of the five complication flags
    (COALESCE(df.aki_flag, 0)
     + COALESCE(df.sepsis_flag, 0)
     + COALESCE(df.mi_flag, 0)
     + COALESCE(df.stroke_flag, 0)
     + COALESCE(df.respfail_flag, 0)) AS composite_score,
    -- death within 90 days of admission (only count deaths on/after admission and within 90 days)
    CASE
      WHEN p.dod IS NOT NULL
       AND DATE_DIFF(DATE(p.dod), DATE(a.admittime), DAY) BETWEEN 0 AND 90
      THEN 1 ELSE 0 END AS death_within_90
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN lower_gi_hadm lg
    ON a.hadm_id = lg.hadm_id
  LEFT JOIN diag_flags df
    ON a.hadm_id = df.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),

quintiled AS (
  -- Assign quintiles by composite score (low -> high)
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM cohort
)

SELECT
  quintile,
  COUNT(*) AS N,
  ROUND(SAFE_DIVIDE(SUM(death_within_90), COUNT(*)) * 100, 2) AS pct_90day_mortality,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN composite_score > 0 THEN 1 ELSE 0 END), COUNT(*)) * 100, 2) AS pct_major_complication,
  -- Median LOS among 90-day survivors in this quintile (approximate median via APPROX_QUANTILES).
  -- If there are no survivors with a non-null LOS in a quintile, median_los_survivors will be NULL.
  APPROX_QUANTILES(
    -- feed only los_days for survivors (death_within_90 = 0) and non-null LOS
    CASE WHEN death_within_90 = 0 AND los_days IS NOT NULL THEN los_days ELSE NULL END,
    100
  )[OFFSET(50)] AS median_los_days_among_90day_survivors
FROM quintiled
GROUP BY quintile
ORDER BY quintile;