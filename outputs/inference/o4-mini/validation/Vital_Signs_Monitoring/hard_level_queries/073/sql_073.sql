WITH
-- 1. Find first ICU stay for each patient
first_icu AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),
-- 2. Cohort: female, age 47–57, ICH diagnosis, first ICU stay
cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.los,
    f.outtime    AS icu_outtime,
    a.deathtime
  FROM
    first_icu f
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON f.subject_id = a.subject_id
     AND f.hadm_id     = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON f.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON f.subject_id = d.subject_id
     AND f.hadm_id     = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    f.rn = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
),
-- 3. Attach the precomputed first-72h instability score (in the ICU dataset)
scores AS (
  SELECT
    c.*,
    v.score_72h
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.first72_vital_instability` v
      ON c.subject_id = v.subject_id
     AND c.stay_id    = v.stay_id
),
-- 4. Compute the percentile rank of a score of 75
percentile_calc AS (
  SELECT
    100.0 * COUNTIF(score_72h < 75) / COUNT(*) AS percentile_of_75
  FROM
    scores
),
-- 5. Determine the 90th‐percentile cutoff for the top decile
decile_cutoff AS (
  SELECT
    APPROX_QUANTILES(score_72h, 10)[OFFSET(8)] AS cutoff_90
  FROM
    scores
),
-- 6. Compute average LOS and mortality rate for the top decile
top_decile_stats AS (
  SELECT
    AVG(los) AS avg_los_top_decile,
    COUNTIF(deathtime <= icu_outtime) * 1.0 / COUNT(*) AS mortality_rate_top_decile
  FROM
    scores s
    CROSS JOIN decile_cutoff d
  WHERE
    s.score_72h >= d.cutoff_90
)
-- 7. Final output: combine percentile and top‐decile stats
SELECT
  p.percentile_of_75,
  t.avg_los_top_decile,
  t.mortality_rate_top_decile
FROM
  percentile_calc p,
  top_decile_stats t;