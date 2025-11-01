WITH cohort_stays AS (
  SELECT
    icu.*,
    adm.hadm_id,
    adm.hospital_expire_flag,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    USING (subject_id, hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    USING (subject_id)
  WHERE
    LOWER(pat.gender) = 'f'
    AND pat.anchor_age BETWEEN 47 AND 57
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
        ON dx.icd_code = dic.icd_code
        AND dx.icd_version = dic.icd_version
      WHERE
        dx.hadm_id = adm.hadm_id
        AND (
          LOWER(dic.long_title) LIKE '%intracran%'
          OR LOWER(dic.long_title) LIKE '%intracerebral%'
          OR LOWER(dic.long_title) LIKE '%subarachnoid%'
          OR LOWER(dic.long_title) LIKE '%subdural%'
          OR LOWER(dic.long_title) LIKE '%epidural%'
          OR LOWER(dic.long_title) LIKE '%cerebral hemorr%'
          OR LOWER(dic.long_title) LIKE '%brain hemorr%'
        )
    )
),

-- Vital sign observations in the first 72 hours of the ICU stay
vitals_obs AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.itemid,
    di.label,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    USING(itemid)
  JOIN
    cohort_stays cs
    ON ce.stay_id = cs.stay_id
  WHERE
    di.category = 'Vital Signs'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 72 HOUR)
),

-- Per-item statistics (mean and sd) across the cohort's first-72-hour observations
stats_by_item AS (
  SELECT
    itemid,
    AVG(valuenum) AS mean_v,
    STDDEV_POP(valuenum) AS sd_v
  FROM
    vitals_obs
  GROUP BY
    itemid
),

-- Attach z-scores per observation (absolute)
obs_with_z AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.itemid,
    v.label,
    v.charttime,
    v.valuenum,
    COALESCE(ABS(SAFE_DIVIDE(v.valuenum - s.mean_v, s.sd_v)), 0) AS abs_z
  FROM
    vitals_obs v
  LEFT JOIN
    stats_by_item s
  USING(itemid)
),

-- Per-stay summed absolute z-score aggregated over first 72 hours, scaled for readability
stay_scores AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    ROUND(SUM(s.abs_z) * 10.0, 2) AS instability_score -- scaled by 10
  FROM
    obs_with_z s
  GROUP BY
    s.stay_id,
    s.subject_id,
    s.hadm_id
),

-- Combine scores with cohort meta data
scores_with_meta AS (
  SELECT
    ss.*,
    cs.los,
    cs.hospital_expire_flag
  FROM
    stay_scores ss
  JOIN
    cohort_stays cs
  USING (stay_id)
),

-- Compute percentile rank for a score of 75
percentile_calc AS (
  SELECT
    COUNTIF(instability_score <= 75) AS n_at_or_below_75,
    COUNT(*) AS n_total,
    ROUND(100.0 * SAFE_DIVIDE(COUNTIF(instability_score <= 75), COUNT(*)), 2) AS percentile_of_75
  FROM
    scores_with_meta
),

-- Determine 90th percentile threshold (approximate) to define top decile
top_decile_threshold AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_threshold
  FROM
    scores_with_meta
),

-- Statistics for the top decile (instability_score >= 90th percentile threshold)
top_decile_stats AS (
  SELECT
    td.p90_threshold,
    COUNT(*) AS n_top_decile,
    ROUND(AVG(sw.los), 3) AS avg_icu_los_days,
    ROUND(100.0 * SAFE_DIVIDE(SUM(sw.hospital_expire_flag), COUNT(*)), 2) AS hospital_mortality_percent
  FROM
    top_decile_threshold td
  JOIN
    scores_with_meta sw
    ON sw.instability_score >= td.p90_threshold
  GROUP BY
    td.p90_threshold
)

-- Final output: percentile for score=75 and top-decile summary
SELECT
  pc.n_at_or_below_75,
  pc.n_total,
  pc.percentile_of_75 AS percentile_of_score_75,
  tds.p90_threshold AS top_decile_threshold_score,
  tds.n_top_decile,
  tds.avg_icu_los_days,
  tds.hospital_mortality_percent
FROM
  percentile_calc pc
CROSS JOIN
  top_decile_stats tds;