WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los AS icu_los,
    adm.hospital_expire_flag,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 88 AND 98
),

-- Identify instability-related items
instability_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN (
    'dialysis',
    'vasopressin',
    'norepinephrine',
    'epinephrine',
    'dopamine',
    'dobutamine',
    'mechanical ventilation',
    'ventilator',
    'peep',
    'tidal volume'
  )
),

-- Compute instability score per stay
instability_scores AS (
  SELECT
    co.stay_id,
    COUNT(ce.itemid) AS instability_score
  FROM
    cohort co
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON co.stay_id = ce.stay_id
  JOIN
    instability_items ii
    ON ce.itemid = ii.itemid
  WHERE
    ce.charttime >= co.intime
    AND ce.charttime <= DATETIME_ADD(co.intime, INTERVAL 72 HOUR)
  GROUP BY
    co.stay_id
),

-- Add scores to cohort
cohort_with_scores AS (
  SELECT
    co.*,
    COALESCE(isc.instability_score, 0) AS instability_score
  FROM
    cohort co
  LEFT JOIN
    instability_scores isc
    ON co.stay_id = isc.stay_id
),

-- Percentile of score 85
percentile_85 AS (
  SELECT
    PERCENT_RANK() OVER (ORDER BY instability_score) * 100 AS percentile_rank_85
  FROM
    cohort_with_scores
  WHERE
    instability_score = 85
  LIMIT 1
),

-- Top quartile (75th percentile and above)
top_quartile AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
  FROM
    cohort_with_scores
)

-- Final output
SELECT
  (SELECT percentile_rank_85 FROM percentile_85) AS percentile_of_score_85,
  AVG(CASE WHEN quartile = 1 THEN icu_los END) AS avg_icu_los_top_quartile,
  AVG(CASE WHEN quartile = 1 THEN hospital_expire_flag END) AS hospital_mortality_top_quartile
FROM
  top_quartile;