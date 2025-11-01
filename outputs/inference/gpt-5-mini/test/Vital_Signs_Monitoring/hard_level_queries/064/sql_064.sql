WITH
-- Identify MAP and HR related itemids dynamically from icu d_items
itemid_flags AS (
  SELECT
    itemid,
    label,
    abbreviation,
    CASE
      WHEN LOWER(label) LIKE '%mean arterial pressure%' THEN 'MAP'
      WHEN LOWER(label) LIKE '%arterial bp mean%' THEN 'MAP'
      WHEN LOWER(label) LIKE '%arterial blood pressure mean%' THEN 'MAP'
      WHEN LOWER(label) LIKE '%map%' AND NOT LOWER(label) LIKE '%map %note%' THEN 'MAP'
      WHEN LOWER(label) LIKE '%mean bp%' THEN 'MAP'
      WHEN LOWER(label) LIKE '%heart rate%' THEN 'HR'
      WHEN LOWER(label) LIKE '%hr %' THEN 'HR'
      WHEN LOWER(abbreviation) = 'hr' THEN 'HR'
      ELSE NULL
    END AS vital_type
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%mean%' OR LOWER(label) LIKE '%heart%' OR LOWER(abbreviation) LIKE '%hr%' OR LOWER(label) LIKE '%map%'
),
map_hr_itemids AS (
  SELECT itemid, vital_type
  FROM itemid_flags
  WHERE vital_type IN ('MAP','HR')
),

-- Gather chartevents in first 48 hours for MAP and HR with numeric values
ce_first48 AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.itemid,
    di.label,
    di.abbreviation,
    CASE WHEN LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%' OR LOWER(di.abbreviation) LIKE '%map%' THEN TRUE ELSE FALSE END AS is_map,
    CASE WHEN LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.abbreviation) = 'hr' OR LOWER(di.label) LIKE '%hr %' THEN TRUE ELSE FALSE END AS is_hr,
    c.charttime,
    c.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON c.stay_id = icu.stay_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  WHERE
    -- Restrict to first 48 hours of ICU stay
    c.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    -- numeric values only
    AND c.valuenum IS NOT NULL
    -- include candidate MAP/HR labels (keeps rows even if di.label is somewhat different; itemid_flags filters below)
    AND (
      LOWER(di.label) LIKE '%mean%' OR LOWER(di.label) LIKE '%arterial%' OR LOWER(di.label) LIKE '%heart%' OR LOWER(di.abbreviation) LIKE '%hr%'
    )
),

-- Aggregate per ICU stay the counts of MAP/HR measurements and abnormal counts
per_stay_counts AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    p.gender,
    SUM(CASE WHEN cf.is_map THEN 1 ELSE 0 END) AS map_total,
    SUM(CASE WHEN cf.is_map AND cf.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    SUM(CASE WHEN cf.is_hr THEN 1 ELSE 0 END) AS hr_total,
    SUM(CASE WHEN cf.is_hr AND cf.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high_count
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    LEFT JOIN ce_first48 cf USING(stay_id)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  GROUP BY
    icu.stay_id, icu.subject_id, icu.hadm_id, icu.intime, icu.outtime, icu.los, p.anchor_age, p.gender
),

-- Compute percent abnormal and composite score for male patients aged 45-55
per_stay_scores AS (
  SELECT
    s.*,
    CASE WHEN map_total > 0 THEN SAFE_DIVIDE(CAST(map_low_count AS FLOAT64), CAST(map_total AS FLOAT64)) ELSE NULL END AS pct_map_low,
    CASE WHEN hr_total > 0 THEN SAFE_DIVIDE(CAST(hr_high_count AS FLOAT64), CAST(hr_total AS FLOAT64)) ELSE NULL END AS pct_hr_high,
    -- Composite score: sum of percent abnormalities (missing component treated as 0)
    COALESCE(CASE WHEN map_total > 0 THEN SAFE_DIVIDE(CAST(map_low_count AS FLOAT64), CAST(map_total AS FLOAT64)) ELSE NULL END, 0.0)
    + COALESCE(CASE WHEN hr_total > 0 THEN SAFE_DIVIDE(CAST(hr_high_count AS FLOAT64), CAST(hr_total AS FLOAT64)) ELSE NULL END, 0.0) AS composite_score
  FROM per_stay_counts s
  WHERE
    -- restrict to male patients age 45-55 inclusive
    s.gender = 'M'
    AND s.anchor_age BETWEEN 45 AND 55
),

-- Compute percentile thresholds (95th and 75th) across the cohort of interest
percentile_thresholds AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(95)] AS pct95_composite,
    APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] AS pct75_composite
  FROM per_stay_scores
),

-- Label top quartile and prepare outcomes
labeled AS (
  SELECT
    s.*,
    t.pct75_composite,
    CASE WHEN s.composite_score >= t.pct75_composite THEN 1 ELSE 0 END AS is_top_quartile
  FROM per_stay_scores s
  CROSS JOIN percentile_thresholds t
),

outcomes AS (
  -- join to admissions for hospital_expire_flag for mortality
  SELECT
    l.stay_id,
    l.subject_id,
    l.hadm_id,
    l.is_top_quartile,
    -- any hypotension (MAP < 65) during first 48h
    CASE WHEN l.map_low_count > 0 THEN 1 ELSE 0 END AS any_hypotension,
    -- any tachycardia (HR > 100) during first 48h
    CASE WHEN l.hr_high_count > 0 THEN 1 ELSE 0 END AS any_tachycardia,
    l.los,
    adm.hospital_expire_flag
  FROM labeled l
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON l.hadm_id = adm.hadm_id
)

-- Final combined output: 1) single-row 95th percentile metric, then 2) top-quartile vs rest comparison rows
SELECT
  'percentile' AS result_type,
  'composite_95th_percentile' AS metric,
  pct95_composite AS value,
  NULL AS group_name,
  NULL AS n_stays,
  NULL AS pct_any_hypotension,
  NULL AS pct_any_tachycardia,
  NULL AS median_icu_los_days,
  NULL AS pct_hospital_mortality,
  2 AS ord
FROM percentile_thresholds

UNION ALL

SELECT
  'comparison' AS result_type,
  NULL AS metric,
  NULL AS value,
  CASE WHEN is_top_quartile = 1 THEN 'Top Quartile' ELSE 'Rest (<=75th pct)' END AS group_name,
  COUNT(*) AS n_stays,
  ROUND(100.0 * AVG(CAST(any_hypotension AS FLOAT64)), 2) AS pct_any_hypotension,
  ROUND(100.0 * AVG(CAST(any_tachycardia AS FLOAT64)), 2) AS pct_any_tachycardia,
  -- median ICU LOS (approx)
  CAST(APPROX_QUANTILES(los, 2)[OFFSET(1)] AS FLOAT64) AS median_icu_los_days,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS pct_hospital_mortality,
  CASE WHEN is_top_quartile = 1 THEN 1 ELSE 0 END AS ord
FROM outcomes
GROUP BY is_top_quartile

ORDER BY ord DESC;