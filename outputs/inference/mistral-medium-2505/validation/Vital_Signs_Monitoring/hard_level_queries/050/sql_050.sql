WITH
-- Get female patients aged 52-62
female_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 52 AND 62
),

-- Identify patients who received RRT (using procedure codes and chart events)
rrt_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.hadm_id = proc.hadm_id
  WHERE
    -- RRT procedure codes (ICD-9/10)
    (proc.icd_code IN ('39.95', '5A1D60Z', '5A1D70Z', '5A1D80Z', '5A1D90Z')
     OR proc.icd_code LIKE '5A1D%')
    -- Or chart events indicating RRT
    OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.subject_id = p.subject_id
        AND ce.hadm_id = p.hadm_id
        AND ce.stay_id = p.stay_id
        AND ce.itemid IN (223900, 223901) -- Example RRT itemids
    )
),

-- Calculate vital-sign instability score for first 72 hours
vital_scores AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.stay_id,
    -- Calculate a simple instability score (example formula)
    -- This is a placeholder - adjust based on actual clinical definition
    (AVG(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) * 0.3 +  -- Heart Rate
     AVG(CASE WHEN ce.itemid = 220050 THEN ce.valuenum ELSE NULL END) * 0.2 +  -- Systolic BP
     AVG(CASE WHEN ce.itemid = 220210 THEN ce.valuenum ELSE NULL END) * 0.3 +  -- Respiratory Rate
     AVG(CASE WHEN ce.itemid = 220277 THEN ce.valuenum ELSE NULL END) * 0.2) AS instability_score -- SpO2
  FROM
    rrt_patients r
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON r.subject_id = ce.subject_id
    AND r.hadm_id = ce.hadm_id
    AND r.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN r.intime AND DATETIME_ADD(r.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (220045, 220050, 220210, 220277) -- Heart rate, BP, RR, SpO2
  GROUP BY
    r.subject_id, r.hadm_id, r.stay_id
),

-- Get percentile rank for score of 65
percentile_info AS (
  SELECT
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank
  FROM
    vital_scores
  WHERE
    instability_score IS NOT NULL
),

-- Calculate the 90th percentile threshold
percentile_threshold AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) AS threshold
  FROM
    vital_scores
  WHERE
    instability_score IS NOT NULL
),

-- Get mean LOS and mortality for top decile
top_decile_stats AS (
  SELECT
    AVG(i.los) AS mean_icu_los,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
  FROM
    vital_scores vs
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON vs.subject_id = i.subject_id
    AND vs.hadm_id = i.hadm_id
    AND vs.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON vs.hadm_id = a.hadm_id
  CROSS JOIN
    percentile_threshold pt
  WHERE
    vs.instability_score >= pt.threshold
)

-- Final results
SELECT
  (SELECT percentile_rank FROM percentile_info WHERE instability_score = 65) AS percentile_for_score_65,
  (SELECT mean_icu_los FROM top_decile_stats) AS mean_icu_los_top_decile,
  (SELECT mortality_rate FROM top_decile_stats) AS mortality_rate_top_decile;