WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime,
    icu.los,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 88 AND 98
),

-- Step 2: Identify RRT stays in first 72h
rrt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%cvvh%' OR
    LOWER(label) LIKE '%cvvhd%' OR
    LOWER(label) LIKE '%cvvhdf%' OR
    LOWER(label) LIKE '%dialysis%' OR
    LOWER(category) LIKE '%dialysis%'
),

rrt_stays AS (
  SELECT DISTINCT
    pe.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN rrt_items di ON pe.itemid = di.itemid
    JOIN cohort c ON pe.stay_id = c.stay_id
  WHERE
    TIMESTAMP_DIFF(pe.starttime, c.icu_intime, HOUR) BETWEEN 0 AND 72
),

-- Step 3: Get instability scores in first 72h (using SAPS II from chartevents)
instability AS (
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS score -- use max SAPS II in first 72h
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN cohort c ON ce.stay_id = c.stay_id
  WHERE
    ce.itemid = 211 -- SAPS II score
    AND ce.valuenum IS NOT NULL
    AND TIMESTAMP_DIFF(ce.charttime, c.icu_intime, HOUR) BETWEEN 0 AND 72
  GROUP BY ce.stay_id
),

-- Step 4: Final cohort: male, aged 88-98, on RRT, with instability score
final_cohort AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.icu_intime,
    c.icu_outtime,
    c.los,
    c.anchor_age,
    instability.score
  FROM
    cohort c
    JOIN rrt_stays rrt ON c.stay_id = rrt.stay_id
    JOIN instability ON c.stay_id = instability.stay_id
),

-- Step 5: Compute percentile of score 85
score_percentile AS (
  SELECT
    COUNTIF(score < 85) AS below_85,
    COUNT(*) AS total,
    SAFE_DIVIDE(COUNTIF(score < 85), COUNT(*)) * 100 AS percentile_85
  FROM final_cohort
),

-- Step 6: Most unstable quartile (top 25%)
quartile_cutoff AS (
  SELECT
    APPROX_QUANTILES(score, 4)[OFFSET(3)] AS q3 -- 75th percentile cutoff
  FROM final_cohort
),

most_unstable AS (
  SELECT
    fc.*,
    adm.hospital_expire_flag
  FROM
    final_cohort fc
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON fc.hadm_id = adm.hadm_id
    JOIN quartile_cutoff qc ON TRUE
  WHERE
    fc.score >= qc.q3
)

-- Output: combine scalar percentile and aggregate most_unstable results
SELECT
  sp.percentile_85 AS percentile_of_85,
  agg.n_most_unstable,
  agg.avg_icu_los,
  agg.n_hosp_deaths,
  agg.hosp_mortality_rate
FROM score_percentile sp
CROSS JOIN (
  SELECT
    COUNT(most.stay_id) AS n_most_unstable,
    AVG(most.los) AS avg_icu_los,
    SUM(most.hospital_expire_flag) AS n_hosp_deaths,
    SAFE_DIVIDE(SUM(most.hospital_expire_flag), COUNT(most.stay_id)) AS hosp_mortality_rate
  FROM most_unstable most
) agg;