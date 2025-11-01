WITH cohort AS (
  -- Base cohort: female, age 52-62, with ICU stay and RRT
  SELECT DISTINCT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    AVG(ic.los) AS mean_los,  -- Mean LOS across stays
    MAX(CAST(COALESCE(a.hospital_expire_flag, 0) AS FLOAT)) AS mortality  -- 1 if died in any admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON p.subject_id = ic.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON ic.subject_id = a.subject_id AND ic.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND p.anchor_age >= 16  -- Exclude neonates
    AND EXISTS (
      -- Subquery: Patient had RRT in any ICU stay
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` ic2
      INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
        ON ic2.subject_id = ie.subject_id 
        AND ic2.hadm_id = ie.hadm_id 
        AND ic2.stay_id = ie.stay_id
        AND ie.itemid BETWEEN 225798 AND 225811  -- CRRT itemids
        AND ie.starttime >= ic2.intime 
        AND ie.starttime <= ic2.outtime
        AND ie.amount > 0  -- Actual administration
      INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
        ON ie.itemid = di.itemid
      WHERE ic2.subject_id = p.subject_id
    )
  GROUP BY p.subject_id, p.anchor_age, p.gender
),

vitals_abnormal AS (
  -- Abnormal vitals in first 72h of each stay
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    di.itemid,
    di.label,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON ce.subject_id = ic.subject_id 
    AND ce.hadm_id = ic.hadm_id 
    AND ce.stay_id = ic.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= ic.intime
    AND ce.charttime <= TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
    AND di.category IN ('Routine Vital Signs', 'Respiratory')  -- Vitals
    AND ce.valuenum IS NOT NULL
    AND (
      -- Abnormal flags (clinical thresholds)
      (di.itemid = 220045 AND (ce.valuenum > 100 OR ce.valuenum < 60)) OR  -- HR
      (di.itemid = 220182 AND (ce.valuenum > 30 OR ce.valuenum < 12)) OR   -- RR
      (di.itemid = 220179 AND (ce.valuenum < 90 OR ce.valuenum > 180)) OR  -- SBP
      (di.itemid = 220180 AND ce.valuenum < 60) OR                         -- DBP
      (di.itemid = 676 AND (ce.valuenum > 38.5 OR ce.valuenum < 36)) OR    -- Temp C
      (di.itemid = 220277 AND ce.valuenum < 92)                            -- SpO2
    )
),

stay_scores AS (
  -- Per-stay instability: (abnormal events / hours in first 72h) * 100
  SELECT 
    va.subject_id,
    va.stay_id,
    COUNT(*) AS abnormal_count,
    EXTRACT(HOUR FROM TIMESTAMP_DIFF(
      LEAST(ic.outtime, TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)), 
      ic.intime
    )) + 1 AS obs_hours,  -- Approximate hours (safe for <=72h)
    (COUNT(*) / NULLIF((EXTRACT(HOUR FROM TIMESTAMP_DIFF(
      LEAST(ic.outtime, TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)), 
      ic.intime
    )) + 1), 0.0)) * 100 AS stay_instability_score
  FROM vitals_abnormal va
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON va.subject_id = ic.subject_id AND va.stay_id = ic.stay_id
  GROUP BY va.subject_id, va.stay_id, ic.intime, ic.outtime
),

instability_scores AS (
  -- Average score across stays per patient
  SELECT 
    subject_id,
    AVG(stay_instability_score) AS instability_score
  FROM stay_scores
  GROUP BY subject_id
),

patient_scores AS (
  SELECT 
    c.*,
    COALESCE(is.instability_score, 0) AS score,
    PERCENT_RANK() OVER (ORDER BY COALESCE(is.instability_score, 0)) AS percentile_rank
  FROM cohort c
  LEFT JOIN instability_scores is ON c.subject_id = is.subject_id
),

percentile_for_65 AS (
  SELECT 
    PERCENT_RANK() OVER (ORDER BY score) * 100 AS percentile_65
  FROM patient_scores
  WHERE score = 65  -- Exact match for score 65; use ABS(score - 65) = 0 if needed
),

top_decile AS (
  SELECT 
    AVG(mean_los) AS top_decile_mean_los,
    AVG(mortality) AS top_decile_mortality_rate
  FROM patient_scores
  WHERE percentile_rank >= 0.9
)

-- Main results
SELECT 
  p.percentile_65 AS target_percentile_65,
  t.top_decile_mean_los,
  t.top_decile_mortality_rate
FROM percentile_for_65 p
CROSS JOIN top_decile t;