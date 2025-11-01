WITH
-- 1. Cohort of female pneumonia ICU patients age 55-65
pneumo AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id   = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pt
      ON icu.subject_id = pt.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON icu.subject_id = dx.subject_id
     AND icu.hadm_id   = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
      ON dx.icd_code    = dicd.icd_code
     AND dx.icd_version = dicd.icd_version
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 55 AND 65
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
),
-- 2. Instability scores in first 24h (assumed precomputed in the ICU dataset)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    instability_score
  FROM
    `physionet-data.mimiciv_3_1_icu.instability_scores`
),
-- 3. Join cohort to scores and compute percentile rank
ranked AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.los,
    p.hospital_expire_flag,
    s.instability_score,
    PERCENT_RANK() OVER (ORDER BY s.instability_score) AS percent_rank
  FROM
    pneumo AS p
    JOIN instability_scores AS s
      ON p.subject_id = s.subject_id
     AND p.hadm_id    = s.hadm_id
     AND p.stay_id    = s.stay_id
),
-- 4. Extract the percentile for score = 60
score_60_pct AS (
  SELECT
    60                                  AS instability_score,
    MAX(percent_rank)                   AS percentile_of_60
  FROM
    ranked
  WHERE
    instability_score = 60
),
-- 5. Define the top (most unstable) decile and compute LOS & mortality
top_decile_stats AS (
  SELECT
    ROUND(AVG(los), 2)                                         AS avg_icu_los_days,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 1)  AS icu_mortality_percent
  FROM
    ranked
  WHERE
    percent_rank >= 0.9
)
-- 6. Combine results
SELECT
  'Percentile of score=60'           AS metric,
  CAST(percentile_of_60 * 100 AS STRING) || '%'              AS value
FROM
  score_60_pct

UNION ALL

SELECT
  'Top decile average ICU LOS (days)' AS metric,
  CAST(avg_icu_los_days AS STRING)      AS value
FROM
  top_decile_stats

UNION ALL

SELECT
  'Top decile ICU mortality rate'     AS metric,
  CAST(icu_mortality_percent AS STRING) || '%'                AS value;