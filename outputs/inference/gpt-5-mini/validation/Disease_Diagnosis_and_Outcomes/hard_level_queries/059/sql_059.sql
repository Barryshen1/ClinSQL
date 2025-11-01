WITH
-- 1) enhanced diagnoses with readable titles (join on icd_code + icd_version)
diag_enhanced AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    LOWER(diag.long_title) AS long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code
   AND d.icd_version = diag.icd_version
),

-- 2) admissions that have any diagnosis mentioning ketoacidosis (DKA)
dka_hadm AS (
  SELECT DISTINCT hadm_id
  FROM diag_enhanced
  WHERE long_title LIKE '%ketoacidosis%'
),

-- 3) per-admission proxy risk score: count distinct diagnosis codes excluding acute diagnoses and DKA
hadm_risk AS (
  SELECT
    hadm_id,
    COALESCE(COUNT(DISTINCT icd_code), 0) AS risk_score
  FROM diag_enhanced
  WHERE NOT (
        long_title LIKE '%ketoacidosis%'    -- exclude DKA itself
    OR  long_title LIKE '%acute%'           -- try to exclude acute diagnoses (AKI, pneumonia, etc.)
    OR  long_title LIKE '%encounter%'       -- exclude encounter/encounter-type titles
    OR  long_title LIKE '%observation%'     -- exclude observation wording
  )
  GROUP BY hadm_id
),

-- 4) per-admission flags for AKI and ARDS (any diagnosis code matching criteria)
hadm_aki_ards AS (
  SELECT
    hadm_id,
    MAX(CASE
          WHEN long_title LIKE '%acute kidney%'
            OR long_title LIKE '%acute renal%'
            OR long_title LIKE '%acute tubular necrosis%'
            OR icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE
          WHEN long_title LIKE '%acute respiratory distress%'
            OR long_title LIKE '%acute respiratory distress syndrome%'
            OR long_title LIKE '%ards%'
            OR icd_code = 'J80' THEN 1 ELSE 0 END) AS has_ards
  FROM diag_enhanced
  GROUP BY hadm_id
),

-- 5) admissions with patient demographics (limit to male, age 59-69)
adm_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE LOWER(COALESCE(p.gender, '')) IN ('m', 'male')
    AND p.anchor_age BETWEEN 59 AND 69
),

-- 6) combine everything per admission for the analytic cohorts
adm_with_metrics AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.dod,
    COALESCE(hr.risk_score, 0) AS risk_score,
    COALESCE(ha.has_aki, 0) AS has_aki,
    COALESCE(ha.has_ards, 0) AS has_ards,
    CASE WHEN dka.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_dka
  FROM adm_base b
  LEFT JOIN hadm_risk hr
    ON b.hadm_id = hr.hadm_id
  LEFT JOIN hadm_aki_ards ha
    ON b.hadm_id = ha.hadm_id
  LEFT JOIN dka_hadm dka
    ON b.hadm_id = dka.hadm_id
),

-- 7) per-admission outcome flags and LOS
adm_outcomes AS (
  SELECT
    *,
    -- 30-day mortality: death date present and within 0..30 days after admission
    CASE
      WHEN dod IS NOT NULL
       AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) BETWEEN 0 AND 30 THEN 1 ELSE 0
    END AS death_30d,
    -- LOS in days (use integer day difference)
    CASE
      WHEN dischtime IS NOT NULL THEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY)
      ELSE NULL
    END AS los_days
  FROM adm_with_metrics
),

-- 8) aggregates for DKA cohort and matched (non-DKA) cohort
cohort_aggregates AS (
  SELECT
    ao.is_dka AS is_dka,
    COUNT(1) AS n_admissions,
    ROUND(AVG(ao.risk_score), 4) AS mean_risk_score,
    SUM(ao.death_30d) AS n_death_30d,
    SAFE_DIVIDE(SUM(ao.death_30d), COUNT(1)) AS mortality_30d_rate,
    SUM(ao.has_aki) AS n_aki,
    SAFE_DIVIDE(SUM(ao.has_aki), COUNT(1)) AS aki_rate,
    SUM(ao.has_ards) AS n_ards,
    SAFE_DIVIDE(SUM(ao.has_ards), COUNT(1)) AS ards_rate,
    -- survivor LOS: mean LOS among admissions without 30-day death
    (SELECT ROUND(AVG(val), 2)
     FROM UNNEST(
       ARRAY(
         SELECT adm2.los_days
         FROM adm_outcomes adm2
         WHERE adm2.is_dka = ao.is_dka
           AND COALESCE(adm2.death_30d, 0) = 0
           AND adm2.los_days IS NOT NULL
       )
     ) AS val
    ) AS mean_survivor_los_days
  FROM adm_outcomes ao
  GROUP BY ao.is_dka
),

-- 9) get the scalar DKA mean risk and matched risk distribution for percentile calculation
dka_mean_and_matched AS (
  SELECT
    -- scalar: mean risk in DKA cohort
    (SELECT mean_risk_score FROM cohort_aggregates WHERE is_dka = 1) AS dka_mean_risk,
    -- matched (non-DKA) distribution: one row per admission with risk_score
    (SELECT ARRAY_AGG(STRUCT(r.hadm_id, r.risk_score) )
     FROM adm_outcomes r
     WHERE r.is_dka = 0) AS matched_rows
)

SELECT
  -- summary table: DKA vs Matched
  ca_dka.n_admissions AS dka_n,
  ca_dka.mean_risk_score AS dka_mean_risk_score,
  ca_dka.mortality_30d_rate AS dka_mortality_30d,
  ca_dka.aki_rate AS dka_aki_rate,
  ca_dka.ards_rate AS dka_ards_rate,
  ca_dka.mean_survivor_los_days AS dka_mean_survivor_los_days,

  ca_mat.n_admissions AS matched_n,
  ca_mat.mean_risk_score AS matched_mean_risk_score,
  ca_mat.mortality_30d_rate AS matched_mortality_30d,
  ca_mat.aki_rate AS matched_aki_rate,
  ca_mat.ards_rate AS matched_ards_rate,
  ca_mat.mean_survivor_los_days AS matched_mean_survivor_los_days,

  -- percentile: percent of matched admissions with risk_score <= DKA mean
  ROUND(100.0 * SAFE_DIVIDE(
    (SELECT COUNTIF(m.risk_score <= dka_stats.dka_mean_risk) FROM UNNEST(dka_stats.matched_rows) m),
    (SELECT COUNT(1) FROM UNNEST(dka_stats.matched_rows) )
  ), 2) AS dka_mean_risk_percentile_among_matched

FROM
  -- pull DKA and matched aggregates as separate rows
  (SELECT * FROM cohort_aggregates WHERE is_dka = 1) AS ca_dka
CROSS JOIN
  (SELECT * FROM cohort_aggregates WHERE is_dka = 0) AS ca_mat
CROSS JOIN
  dka_mean_and_matched AS dka_stats;