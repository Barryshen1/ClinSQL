WITH
-- Get female patients aged 49-59 at ICU admission
female_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    a.hospital_expire_flag,
    -- Calculate age at ICU admission
    p.anchor_age + EXTRACT(YEAR FROM s.intime) - p.anchor_year AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` s ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM s.intime) - p.anchor_year BETWEEN 49 AND 59
),

-- Get vital signs in first 24 hours of ICU stay
vital_signs AS (
  SELECT
    f.subject_id,
    f.stay_id,
    -- Heart rate (itemid 220045)
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS heart_rate,
    -- Systolic BP (itemid 220050)
    MAX(CASE WHEN ce.itemid = 220050 THEN ce.valuenum ELSE NULL END) AS systolic_bp,
    -- Respiratory rate (itemid 220210)
    MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum ELSE NULL END) AS respiratory_rate,
    -- Oxygen saturation (itemid 220277)
    MAX(CASE WHEN ce.itemid = 220277 THEN ce.valuenum ELSE NULL END) AS oxygen_saturation
  FROM
    female_patients f
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON f.subject_id = ce.subject_id AND f.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220045, 220050, 220210, 220277)
  GROUP BY
    f.subject_id, f.stay_id
),

-- Calculate composite instability score (simple average of normalized values)
instability_scores AS (
  SELECT
    v.subject_id,
    v.stay_id,
    -- Normalize each vital sign (assuming ranges)
    (v.heart_rate - 60) / (100 - 60) AS normalized_hr,
    (v.systolic_bp - 90) / (180 - 90) AS normalized_bp,
    (v.respiratory_rate - 12) / (24 - 12) AS normalized_rr,
    (100 - v.oxygen_saturation) / (100 - 90) AS normalized_spo2,
    -- Composite score (average of normalized values)
    ( (v.heart_rate - 60) / (100 - 60) +
      (v.systolic_bp - 90) / (180 - 90) +
      (v.respiratory_rate - 12) / (24 - 12) +
      (100 - v.oxygen_saturation) / (100 - 90) ) / 4 AS composite_score
  FROM
    vital_signs v
),

-- Get the 90th percentile threshold for top decile
percentile_threshold AS (
  SELECT
    PERCENTILE_CONT(composite_score, 0.9) OVER() AS threshold
  FROM
    instability_scores
  LIMIT 1
),

-- Get top decile patients
top_decile AS (
  SELECT
    i.subject_id,
    i.stay_id,
    i.composite_score,
    f.los,
    f.hospital_expire_flag
  FROM
    instability_scores i
  JOIN
    female_patients f ON i.subject_id = f.subject_id AND i.stay_id = f.stay_id
  CROSS JOIN
    percentile_threshold p
  WHERE
    i.composite_score >= p.threshold
)

-- Final results
SELECT
  PERCENTILE_CONT(composite_score, 0.7) OVER() AS percentile_for_score_0_7,
  AVG(los) AS mean_icu_los_top_decile,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS hospital_mortality_percent_top_decile
FROM
  top_decile
LIMIT 1;