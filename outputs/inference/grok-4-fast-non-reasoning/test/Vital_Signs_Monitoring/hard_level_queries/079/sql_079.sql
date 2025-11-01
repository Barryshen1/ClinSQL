WITH qualifying_stays AS (
  -- Base cohort: male, 81-91, ICU stays with HFNC in first 48h
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.los,
    a.hospital_expire_flag,
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND EXISTS (
      -- HFNC usage in first 48h (itemid 228351 for High Flow Nasal Cannula)
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.subject_id = i.subject_id
        AND ce.hadm_id = i.hadm_id
        AND ce.stay_id = i.stay_id
        AND ce.itemid = 228351
        AND ce.charttime >= i.intime
        AND ce.charttime <= i.intime + INTERVAL 2 DAY
        AND ce.value IS NOT NULL  -- Ensure valid event
    )
),

all_scores AS (
  -- All qualifying scores for percentile calculation
  SELECT 
    qs.*,
    (COALESCE(AVG(CASE WHEN ce.itemid = 220045 THEN (ce.valuenum - 60)/20 END), 0) +
     COALESCE(AVG(CASE WHEN ce.itemid = 220210 THEN (ce.valuenum - 12)/10 END), 0) +
     COALESCE(AVG(CASE WHEN ce.itemid = 220277 THEN (100 - ce.valuenum)/10 END), 0)) * 10 AS instability_score
  FROM qualifying_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON qs.subject_id = ce.subject_id
    AND qs.hadm_id = ce.hadm_id
    AND qs.stay_id = ce.stay_id
    AND ce.charttime >= qs.intime
    AND ce.charttime <= qs.intime + INTERVAL 2 DAY
    AND ce.itemid IN (220045, 220210, 220277)
  GROUP BY qs.subject_id, qs.stay_id, qs.hadm_id, qs.los, qs.hospital_expire_flag, qs.intime
),

thresholds AS (
  -- Compute 90th percentile threshold once
  SELECT 
    PERCENTILE_CONT(instability_score, 0.9) AS top_decile_threshold
  FROM all_scores
)

-- Percentile for score = 85 (proportion of scores <= 85)
SELECT 
  'Percentile for score 85' AS metric,
  ROUND(AVG(CASE WHEN instability_score <= 85 THEN 1.0 ELSE 0 END) * 100, 2) AS value
FROM all_scores

UNION ALL

-- Top decile: avg LOS
SELECT 
  'Avg ICU LOS top decile (days)' AS metric,
  ROUND(AVG(los), 2) AS value
FROM all_scores, thresholds
WHERE instability_score >= thresholds.top_decile_threshold

UNION ALL

-- Top decile: mortality %
SELECT 
  'Hospital mortality top decile (%)' AS metric,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS value
FROM all_scores, thresholds
WHERE instability_score >= thresholds.top_decile_threshold;