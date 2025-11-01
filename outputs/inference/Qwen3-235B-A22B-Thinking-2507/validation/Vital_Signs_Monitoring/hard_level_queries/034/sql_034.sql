WITH patients_cohort AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = i.hadm_id
        AND d.icd_code IN ('R578', 'R579')
        AND d.icd_version = 10
    )
),

instability_events AS (
  SELECT 
    c.stay_id,
    c.hadm_id,
    c.intime,
    c.los,
    c.hospital_expire_flag,
    ce.itemid,
    ce.valuenum,
    ce.charttime
  FROM patients_cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (220052, 220045)
    AND ce.valuenum IS NOT NULL
),

instability_scores AS (
  SELECT 
    stay_id,
    los,
    hospital_expire_flag,
    COUNT(CASE WHEN itemid = 220052 AND valuenum < 65 THEN 1 END) AS hypotension_count,
    COUNT(CASE WHEN itemid = 220045 AND valuenum > 100 THEN 1 END) AS tachycardia_count,
    COUNT(CASE WHEN itemid = 220052 AND valuenum < 65 THEN 1 END) + 
    COUNT(CASE WHEN itemid = 220045 AND valuenum > 100 THEN 1 END) AS instability_score
  FROM instability_events
  GROUP BY stay_id, los, hospital_expire_flag
),

cohort_stats AS (
  SELECT
    instability_score,
    hypotension_count,
    tachycardia_count,
    los,
    hospital_expire_flag,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile_rank
  FROM instability_scores
),

percentile_95 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS instability_95th
  FROM cohort_stats
),

cohort_metrics AS (
  SELECT 
    'entire_cohort' AS group_name,
    AVG(hypotension_count) AS hypotension_count,
    AVG(tachycardia_count) AS tachycardia_count,
    AVG(los) AS icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort_stats
  
  UNION ALL
  
  SELECT 
    'top_decile' AS group_name,
    AVG(hypotension_count) AS hypotension_count,
    AVG(tachycardia_count) AS tachycardia_count,
    AVG(los) AS icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort_stats
  WHERE decile_rank = 1
)

-- Return the 95th percentile and comparison metrics
SELECT 
  '95th_percentile_instability_score' AS metric,
  instability_95th AS entire_cohort,
  NULL AS top_decile
FROM percentile_95

UNION ALL

SELECT 
  'hypotension_count_avg' AS metric,
  (SELECT hypotension_count FROM cohort_metrics WHERE group_name = 'entire_cohort') AS entire_cohort,
  (SELECT hypotension_count FROM cohort_metrics WHERE group_name = 'top_decile') AS top_decile
FROM UNNEST([1])

UNION ALL

SELECT 
  'tachycardia_count_avg' AS metric,
  (SELECT tachycardia_count FROM cohort_metrics WHERE group_name = 'entire_cohort') AS entire_cohort,
  (SELECT tachycardia_count FROM cohort_metrics WHERE group_name = 'top_decile') AS top_decile
FROM UNNEST([1])

UNION ALL

SELECT 
  'icu_los_avg' AS metric,
  (SELECT icu_los FROM cohort_metrics WHERE group_name = 'entire_cohort') AS entire_cohort,
  (SELECT icu_los FROM cohort_metrics WHERE group_name = 'top_decile') AS top_decile
FROM UNNEST([1])

UNION ALL

SELECT 
  'mortality_rate' AS metric,
  (SELECT mortality_rate FROM cohort_metrics WHERE group_name = 'entire_cohort') AS entire_cohort,
  (SELECT mortality_rate FROM cohort_metrics WHERE group_name = 'top_decile') AS top_decile
FROM UNNEST([1]);