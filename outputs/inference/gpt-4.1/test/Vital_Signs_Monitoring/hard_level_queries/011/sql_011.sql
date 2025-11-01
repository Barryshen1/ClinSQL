WITH pneumonia_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 55 AND 65
    AND (
      -- ICD-10 pneumonia: J12-J18
      (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^J1[2-8]'))
      -- ICD-9 pneumonia: 480-486
      OR (diag.icd_version = 9 AND CAST(diag.icd_code AS INT64) BETWEEN 480 AND 486)
    )
),

-- Placeholder: Replace with your actual instability score calculation per stay_id
instability_scores AS (
  SELECT
    stay_id,
    -- Simulate instability score (replace with real calculation)
    ABS(CAST(FARM_FINGERPRINT(CAST(stay_id AS STRING)) AS INT64)) % 100 AS instability_score
  FROM
    pneumonia_icustays
),

cohort AS (
  SELECT
    p.*,
    s.instability_score
  FROM
    pneumonia_icustays p
  INNER JOIN
    instability_scores s
    ON p.stay_id = s.stay_id
),

-- Calculate percentile for score=60
percentile_calc AS (
  SELECT
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank
  FROM
    cohort
),

-- Find percentile for score=60
score_percentile AS (
  SELECT
    percentile_rank
  FROM
    percentile_calc
  WHERE
    instability_score = 60
  ORDER BY
    percentile_rank
  LIMIT 1
),

-- Find top decile (most unstable 10%)
decile_cutoff AS (
  SELECT
    APPROX_QUANTILES(instability_score, 10)[OFFSET(9)] AS decile_threshold
  FROM
    cohort
),

top_decile AS (
  SELECT
    c.*,
    a.hospital_expire_flag
  FROM
    cohort c
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
  CROSS JOIN
    decile_cutoff d
  WHERE
    c.instability_score >= d.decile_threshold
)

SELECT
  -- Part 1: Percentile of score 60
  (SELECT percentile_rank FROM score_percentile) AS percentile_of_score_60,
  -- Part 2: ICU LOS and mortality for top decile
  (
    SELECT
      COUNT(*) AS n_top_decile,
      AVG(los) AS avg_icu_los,
      SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
    FROM
      top_decile
  ) AS top_decile_stats;