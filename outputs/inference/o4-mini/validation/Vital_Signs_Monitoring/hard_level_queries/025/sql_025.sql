WITH post_arrest_stays AS (
  -- 1. Male patients age 55-65 with a diagnosis of cardiac arrest
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.deathtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    USING(subject_id, hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        USING(icd_code, icd_version)
      WHERE d.subject_id = icu.subject_id
        AND d.hadm_id = icu.hadm_id
        AND LOWER(dd.long_title) LIKE '%cardiac arrest%'
    )
),
instability_scores AS (
  -- 2. Pull in your precomputed first-24h instability scores from your own project
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    score_24h
  FROM
    `YOUR_PROJECT_ID.mimiciv_derived.instability_scores_24h`
),
scores AS (
  -- 3. Join stays to their instability scores
  SELECT
    pa.*,
    s.score_24h
  FROM post_arrest_stays AS pa
  JOIN instability_scores AS s
    USING(subject_id, hadm_id, stay_id)
),
percentile_calc AS (
  -- 4a. Compute percentile rank of each distinct score
  SELECT
    score_24h,
    PERCENT_RANK() OVER (ORDER BY score_24h) AS pct_rank
  FROM (
    SELECT DISTINCT score_24h
    FROM scores
  )
),
score70_pct AS (
  -- 4b. Extract the percentile for the score = 70
  SELECT
    pct_rank AS percentile_of_70
  FROM percentile_calc
  WHERE score_24h = 70
),
decile_cutoff AS (
  -- 5. Compute the 90th percentile cutoff to define the most unstable decile
  SELECT
    PERCENTILE_CONT(score_24h, 0.9) OVER() AS cutoff_90
  FROM scores
  LIMIT 1
),
top_decile_stats AS (
  -- 6. Compute mean ICU LOS and ICU mortality in the top decile
  SELECT
    AVG(los) AS mean_icu_los,
    100.0 * AVG(
      CASE 
        WHEN deathtime IS NOT NULL 
          AND deathtime <= outtime 
        THEN 1 
        ELSE 0 
      END
    ) AS icu_mortality_pct
  FROM scores, decile_cutoff
  WHERE score_24h >= cutoff_90
)
-- 7. Final output: percentile of 70, and stats for the most unstable decile
SELECT
  s70.percentile_of_70,
  td.mean_icu_los,
  td.icu_mortality_pct
FROM
  score70_pct AS s70
CROSS JOIN
  top_decile_stats AS td;