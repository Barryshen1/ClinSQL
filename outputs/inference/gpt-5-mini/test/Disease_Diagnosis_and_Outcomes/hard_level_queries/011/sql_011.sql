WITH icu_adm AS (
  -- admissions that had an ICU stay during the admission, female patients aged 88-98
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    USING(subject_id, hadm_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),

dxs AS (
  -- all diagnosis descriptions for the included admissions
  SELECT
    ia.hadm_id,
    LOWER(dd.long_title) AS long_title,
    dd.icd_code
  FROM icu_adm ia
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    USING(hadm_id)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
),

flags AS (
  -- per-admission flags for AMI, AKI, ARDS using diagnosis text / code heuristics
  SELECT
    hadm_id,
    MAX(CASE WHEN long_title LIKE '%myocardial infarction%' THEN 1 ELSE 0 END) AS ami_flag,
    MAX(CASE WHEN long_title LIKE '%acute kidney%' OR long_title LIKE '%acute renal%' OR icd_code LIKE '584%' OR icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS aki_flag,
    MAX(CASE WHEN long_title LIKE '%acute respiratory distress%' OR long_title LIKE '%ards%' OR icd_code LIKE '51882%' OR icd_code LIKE 'J80%' THEN 1 ELSE 0 END) AS ards_flag
  FROM dxs
  GROUP BY hadm_id
),

cohort AS (
  -- admissions that meet the AMI criterion (female, age, ICU stay already applied)
  SELECT
    ia.*,
    COALESCE(f.aki_flag, 0) AS aki_flag,
    COALESCE(f.ards_flag, 0) AS ards_flag
  FROM icu_adm ia
  JOIN flags f
    USING(hadm_id)
  WHERE f.ami_flag = 1
),

scored AS (
  -- construct a simple composite score and compute death / survival intervals
  SELECT
    *,
    -- Example composite score (replace with your validated risk score if available)
    (anchor_age + 15 * (aki_flag + ards_flag)) AS composite_score,
    CASE
      WHEN deathtime IS NOT NULL
        AND TIMESTAMP_DIFF(deathtime, admittime, DAY) BETWEEN 0 AND 30 THEN 1
      ELSE 0
    END AS died_within_30d,
    CASE
      WHEN deathtime IS NOT NULL
        AND TIMESTAMP_DIFF(deathtime, admittime, DAY) >= 0
      THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
      ELSE NULL
    END AS survival_days
  FROM cohort
),

ranked AS (
  -- percentile rank of composite score across the cohort (0..1)
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY composite_score) AS composite_risk_percentile
  FROM scored
)

-- Final cohort summary
SELECT
  COUNT(*) AS n_admissions,
  ROUND(100.0 * AVG(composite_risk_percentile), 2) AS avg_composite_risk_percentile_pct,
  ROUND(100.0 * SUM(died_within_30d) / COUNT(*), 2) AS pct_30day_mortality,
  ROUND(100.0 * SUM(aki_flag) / COUNT(*), 2) AS pct_aki,
  ROUND(100.0 * SUM(ards_flag) / COUNT(*), 2) AS pct_ards,
  -- median survival (in days) among decedents (approximate)
  APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days_decedents
FROM ranked;