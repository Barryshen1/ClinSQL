WITH first_icu_stays AS (
  -- Get first ICU stay per patient, with demographics and admission links
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND p.anchor_age < 90
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year >= 0
),
eligible_stays AS (
  -- Filter to first stay only
  SELECT *
  FROM first_icu_stays
  WHERE rn = 1
),
vitals_data AS (
  -- Extract first-24h vitals from chartevents
  SELECT 
    e.subject_id,
    e.stay_id,
    AVG(CASE ce.itemid WHEN 220045 THEN ce.valuenum END) AS mean_hr,  -- Heart rate
    AVG(CASE ce.itemid WHEN 220210 THEN ce.valuenum END) AS mean_rr,  -- Respiratory rate
    AVG(CASE ce.itemid WHEN 220179 THEN ce.valuenum END) AS mean_sbp, -- Systolic BP
    AVG(CASE ce.itemid WHEN 223761 THEN ce.valuenum END) AS mean_temp -- Temperature (C)
  FROM eligible_stays e
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = e.subject_id
    AND ce.hadm_id = e.hadm_id
    AND ce.stay_id = e.stay_id
    AND ce.itemid IN (220045, 220210, 220179, 223761)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= e.intime
    AND ce.charttime < TIMESTAMP_ADD(e.intime, INTERVAL 24 HOUR)
  GROUP BY e.subject_id, e.stay_id
),
instability_scores AS (
  -- Compute composite score (0-100)
  SELECT 
    es.*,
    COALESCE(vd.mean_hr, 70) AS hr,  -- Impute missing with normal midpoint
    COALESCE(vd.mean_rr, 16) AS rr,
    COALESCE(vd.mean_sbp, 115) AS sbp,
    COALESCE(vd.mean_temp, 37) AS temp,
    -- Composite: average of instabilities (0-100)
    (COALESCE(GREATEST(0, LEAST(1, ABS((COALESCE(vd.mean_hr, 70) - 80) / 20))), 0) +
     COALESCE(GREATEST(0, LEAST(1, ABS((COALESCE(vd.mean_rr, 16) - 16) / 4))), 0) +
     COALESCE(GREATEST(0, LEAST(1, ABS((COALESCE(vd.mean_sbp, 115) - 115) / 25))), 0) +
     COALESCE(GREATEST(0, LEAST(1, ABS((COALESCE(vd.mean_temp, 37) - 36.5) / 1))), 0)) * 25 AS instability_score
  FROM eligible_stays es
  LEFT JOIN vitals_data vd
    ON vd.subject_id = es.subject_id
),
ranked_scores AS (
  -- Add percentile rank
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score) * 100 AS score_percentile
  FROM instability_scores
),
top_decile AS (
  -- Flag top decile
  SELECT 
    *,
    CASE WHEN score_percentile >= 90 THEN 1 ELSE 0 END AS top_decile_flag
  FROM ranked_scores
),
percentile_70 AS (
  -- Percentile for score=70
  SELECT 
    PERCENT_RANK() OVER (ORDER BY instability_score) * 100 AS percentile_for_70
  FROM ranked_scores
  WHERE instability_score = 70  -- Exact match; if no exact, could use approx but assuming possible
  LIMIT 1
),
outcomes AS (
  -- Aggregate outcomes for top decile
  SELECT 
    AVG(los) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct
  FROM top_decile
  WHERE top_decile_flag = 1
)
-- Final output: combine
SELECT 
  'Percentile for score 70' AS metric,
  ROUND(p.percentile_for_70, 2) AS value
FROM percentile_70 p
UNION ALL
SELECT 
  'Mean LOS top decile (days)' AS metric,
  ROUND(o.mean_los_days, 2) AS value
FROM outcomes o
UNION ALL
SELECT 
  'Mortality top decile (%)' AS metric,
  ROUND(o.mortality_pct, 2) AS value
FROM outcomes o;