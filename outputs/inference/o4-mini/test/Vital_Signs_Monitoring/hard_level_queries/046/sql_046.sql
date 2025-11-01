WITH cohort AS (
  -- Male ICU patients age 84–94 with ischemic stroke
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
      ON icu.subject_id = diag.subject_id
     AND icu.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddiag
      ON diag.icd_code = ddiag.icd_code
     AND diag.icd_version = ddiag.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND LOWER(ddiag.long_title) LIKE '%infarction%'  -- ischemic stroke
),
instability_scores AS (
  -- Use the precomputed instability score table in the ICU dataset
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    score
  FROM
    `physionet-data.mimiciv_3_1_icu.first_72h_instability_scores`
),
scores_in_cohort AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    s.score
  FROM
    cohort AS c
  JOIN
    instability_scores AS s
      ON c.subject_id = s.subject_id
     AND c.hadm_id = s.hadm_id
     AND c.stay_id = s.stay_id
),
percentiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los,
    hospital_expire_flag,
    score,
    PERCENT_RANK() OVER (ORDER BY score) AS pct_rank
  FROM
    scores_in_cohort
),
percentile_of_80 AS (
  -- What percentile is a score of 80?
  SELECT
    MAX(pct_rank) AS percentile_for_80
  FROM
    percentiles
  WHERE
    score <= 80
),
top_quartile AS (
  -- Identify stays in the top instability quartile
  SELECT
    los,
    hospital_expire_flag
  FROM
    percentiles
  WHERE
    pct_rank >= 0.75
),
metrics_top_quartile AS (
  -- Compute average LOS and mortality rate among the top quartile
  SELECT
    AVG(los) AS avg_icu_los_top_quartile,
    AVG(hospital_expire_flag) AS mortality_rate_top_quartile
  FROM
    top_quartile
)
SELECT
  p80.percentile_for_80 AS percentile_score_80,
  m.avg_icu_los_top_quartile,
  m.mortality_rate_top_quartile
FROM
  percentile_of_80 AS p80
CROSS JOIN
  metrics_top_quartile AS m;