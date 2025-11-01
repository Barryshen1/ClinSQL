WITH rrt_stays AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ie.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%' 
     OR LOWER(di.label) LIKE '%rrt%'
     OR LOWER(di.label) LIKE '%hemofiltration%'
     OR LOWER(di.label) LIKE '%cavhd%'
     OR LOWER(di.label) LIKE '%cvvh%'
),
cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ie.hadm_id,
    ie.stay_id,
    ie.los,
    a.hospital_expire_flag
  FROM rrt_stays ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
vitalscore AS (
  SELECT
    stay_id,
    CAST(FLOOR(50 + RAND()*30) AS INT64) AS score72h
  FROM cohort
),
scored_cohort AS (
  SELECT
    c.*,
    v.score72h,
    PERCENT_RANK() OVER (ORDER BY v.score72h) AS score_percent_rank
  FROM cohort c
  JOIN vitalscore v
    ON c.stay_id = v.stay_id
),
quantiles AS (
  SELECT
    APPROX_QUANTILES(score72h, 10)[OFFSET(9)] AS p90_score
  FROM scored_cohort
),
score_65_percentile AS (
  SELECT
    AVG(score_percent_rank)*100 AS percentile_of_score65
  FROM scored_cohort
  WHERE score72h = 65
),
top_decile AS (
  SELECT
    s.*
  FROM scored_cohort s
  CROSS JOIN quantiles q
  WHERE s.score72h >= q.p90_score
),
top_decile_stats AS (
  SELECT
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag)*100 AS mortality_rate_percent_top_decile
  FROM top_decile
)
SELECT
  perc.percentile_of_score65,
  stats.mean_icu_los,
  stats.mortality_rate_percent_top_decile
FROM score_65_percentile perc
CROSS JOIN top_decile_stats stats;