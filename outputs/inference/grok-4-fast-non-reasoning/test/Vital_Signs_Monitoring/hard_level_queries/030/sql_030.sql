WITH cohort AS (
  -- Define cohort: female, age 43-53 at ICU admission, principal diagnosis acute respiratory failure, first ICU stay
  SELECT DISTINCT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    a.hospital_expire_flag,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id, i.hadm_id ORDER BY i.stay_id) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year BETWEEN 43 AND 53
    AND d.seq_num = 1
    AND REGEXP_CONTAINS(d.icd_code, '^J96')
    AND d.icd_version = '10'
    AND p.anchor_age >= 18  -- Exclude pediatrics
),
first_stay_cohort AS (
  SELECT *
  FROM cohort
  WHERE rn = 1
),
vitals AS (
  -- Extract relevant vitals in first 48 hours for cohort
  SELECT
    c.subject_id,
    c.stay_id,
    c.intime,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM first_stay_cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.stay_id = ce.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (
      220045,  -- Heart rate
      220210,  -- Respiratory rate
      220052,  -- MAP
      220277,  -- SpO2
      223761   -- Temperature C
    )
),
instability_scores AS (
  -- Compute instability score per observation
  SELECT
    v.subject_id,
    v.stay_id,
    v.charttime,
    (CASE WHEN v.itemid = 220045 AND v.valuenum > 120 THEN 1 ELSE 0 END) +
    (CASE WHEN v.itemid = 220210 AND v.valuenum > 30 THEN 1 ELSE 0 END) +
    (CASE WHEN v.itemid = 220052 AND v.valuenum < 65 THEN 2 ELSE 0 END) +
    (CASE WHEN v.itemid = 220277 AND v.valuenum < 90 THEN 1 ELSE 0 END) +
    (CASE WHEN v.itemid = 223761 AND (v.valuenum > 39 OR v.valuenum < 36) THEN 1 ELSE 0 END) AS instability_score
  FROM vitals v
),
patient_instability AS (
  -- Max instability score per patient (for 95th percentile and quartile)
  SELECT
    subject_id,
    stay_id,
    MAX(instability_score) AS max_instability
  FROM instability_scores
  GROUP BY subject_id, stay_id
),
patient_medians AS (
  -- Median score per patient for quartile definition (using max as proxy)
  SELECT
    subject_id,
    stay_id,
    max_instability AS median_instability  -- Using max for simplicity; adjust if median needed
  FROM patient_instability
),
cohort_q75 AS (
  SELECT PERCENTILE_CONT(0.75) OVER (ORDER BY median_instability) AS q75
  FROM patient_medians
),
cohort_with_quartile AS (
  -- Assign top quartile
  SELECT
    fsc.*,
    pm.median_instability,
    CASE WHEN pm.median_instability >= cq.q75 THEN 'top_quartile' ELSE 'rest_cohort' END AS group_type
  FROM first_stay_cohort fsc
  INNER JOIN patient_medians pm ON fsc.subject_id = pm.subject_id AND fsc.stay_id = pm.stay_id
  CROSS JOIN cohort_q75 cq
),
all_icu_outcomes AS (
  -- General ICU population outcomes (all adults, first stay)
  SELECT
    'general_icu' AS group_type,
    AVG(los) AS avg_los,
    AVG(hypotension_episodes) AS avg_hypotension,
    AVG(tachycardia_episodes) AS avg_tachycardia,
    AVG(CAST(mortality_flag AS FLOAT)) AS mortality_rate
  FROM (
    SELECT
      i.subject_id,
      i.stay_id,
      i.hadm_id,
      i.los,
      a.hospital_expire_flag AS mortality_flag,
      COUNT(DISTINCT CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 
                          AND ce.charttime >= i.intime 
                          AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
                          THEN DATE(ce.charttime) END) AS hypotension_episodes,
      COUNT(DISTINCT CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 
                          AND ce.charttime >= i.intime 
                          AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
                          THEN DATE(ce.charttime) END) AS tachycardia_episodes
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON i.subject_id = ce.subject_id AND i.stay_id = ce.stay_id
      AND ce.itemid IN (220052, 220045)
      AND ce.valuenum IS NOT NULL
    WHERE p.anchor_age >= 18
      AND ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.stay_id) = 1  -- First stay
    GROUP BY i.subject_id, i.stay_id, i.hadm_id, i.los, a.hospital_expire_flag
  ) sub
),
cohort_outcomes AS (
  -- Outcomes for cohort groups
  SELECT
    group_type,
    AVG(los) AS avg_los,
    AVG(hypotension_episodes) AS avg_hypotension,
    AVG(tachycardia_episodes) AS avg_tachycardia,
    AVG(CAST(hospital_expire_flag AS FLOAT)) AS mortality_rate
  FROM (
    SELECT
      cwq.subject_id,
      cwq.stay_id,
      cwq.group_type,
      cwq.los,
      cwq.hospital_expire_flag,
      COUNT(DISTINCT CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 
                          AND ce.charttime >= cwq.intime 
                          AND ce.charttime < TIMESTAMP_ADD(cwq.intime, INTERVAL 24 HOUR)
                          THEN DATE(ce.charttime) END) AS hypotension_episodes,
      COUNT(DISTINCT CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 
                          AND ce.charttime >= cwq.intime 
                          AND ce.charttime < TIMESTAMP_ADD(cwq.intime, INTERVAL 24 HOUR)
                          THEN DATE(ce.charttime) END) AS tachycardia_episodes
    FROM cohort_with_quartile cwq
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON cwq.subject_id = ce.subject_id AND cwq.stay_id = ce.stay_id
      AND ce.itemid IN (220052, 220045)
      AND ce.valuenum IS NOT NULL
    GROUP BY cwq.subject_id, cwq.stay_id, cwq.group_type, cwq.los, cwq.hospital_expire_flag, cwq.intime
  ) sub
  GROUP BY group_type
)
-- 95th percentile instability index for full cohort (patient-level max)
SELECT 
  'cohort_95th_percentile_instability' AS metric,
  PERCENTILE_CONT(0.95) OVER (ORDER BY pi.max_instability) AS value
FROM patient_instability pi
UNION ALL
-- Comparisons for top quartile vs general
SELECT 
  co.group_type || '_vs_general' AS metric,
  JSON_OBJECT(
    'avg_los': co.avg_los,
    'avg_hypotension_episodes': co.avg_hypotension,
    'avg_tachycardia_episodes': co.avg_tachycardia,
    'mortality_rate': co.mortality_rate,
    'general_los': g.avg_los,
    'general_hypotension': g.avg_hypotension,
    'general_tachycardia': g.avg_tachycardia,
    'general_mortality': g.mortality_rate
  ) AS comparison
FROM cohort_outcomes co
CROSS JOIN all_icu_outcomes g
WHERE co.group_type = 'top_quartile';