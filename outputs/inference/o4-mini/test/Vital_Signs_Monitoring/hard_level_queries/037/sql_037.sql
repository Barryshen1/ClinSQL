WITH
-- 1. Identify itemids for HR, MAP, RR
vitals_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label IN ('Heart Rate', 'Mean Arterial Pressure', 'Respiratory Rate')
),

-- 2. Build the ICU cohort: male, age 45-55, with heart failure
hf_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.subject_id = a.subject_id
   AND icu.hadm_id   = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    -- will filter heart failure next
),

hf_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),

hf_cohort2 AS (
  SELECT c.*
  FROM hf_cohort c
  JOIN hf_admissions h
    ON c.hadm_id = h.hadm_id
),

-- 3. Extract and flag the vital sign abnormalities in first 72h
vitals_72h AS (
  SELECT
    c.stay_id,
    ce.itemid,
    i.label,
    ce.valuenum,
    CASE 
      WHEN i.label = 'Heart Rate' AND ce.valuenum > 100 THEN 1 
      ELSE 0 
    END AS is_tachy,
    CASE 
      WHEN i.label = 'Mean Arterial Pressure' AND ce.valuenum < 65 THEN 1 
      ELSE 0 
    END AS is_hypotn,
    CASE 
      WHEN i.label = 'Respiratory Rate' AND ce.valuenum > 20 THEN 1 
      ELSE 0 
    END AS is_tachypnea
  FROM hf_cohort2 c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
   AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  JOIN vitals_items i
    ON ce.itemid = i.itemid
  WHERE ce.valuenum IS NOT NULL
),

-- 4. Sum up per stay to form the composite score
scores AS (
  SELECT
    stay_id,
    SUM(is_tachy)     AS cnt_tachy,
    SUM(is_hypotn)    AS cnt_hypotn,
    SUM(is_tachypnea) AS cnt_tachypnea,
    (SUM(is_tachy) + SUM(is_hypotn) + SUM(is_tachypnea)) AS composite_score
  FROM vitals_72h
  GROUP BY stay_id
),

-- 5. Attach back LOS and mortality
scores_full AS (
  SELECT
    s.*,
    c.los,
    c.hospital_expire_flag
  FROM scores s
  JOIN hf_cohort2 c
    ON s.stay_id = c.stay_id
),

-- 6. Compute percentiles for composite score
percentiles AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(99)] AS p99,
    APPROX_QUANTILES(composite_score,   4)[OFFSET(3)] AS q3
  FROM scores_full
),

-- 7. Tag top‐quartile stays
tagged AS (
  SELECT
    sf.*,
    p.p99,
    p.q3,
    CASE WHEN sf.composite_score > p.q3 THEN 'top_quartile' ELSE 'other' END AS quartile_grp
  FROM scores_full sf
  CROSS JOIN percentiles p
),

-- 8. Compute metrics for top quartile vs entire cohort
metrics AS (
  SELECT
    quartile_grp,
    COUNT(1) AS n_stays,
    AVG(cnt_tachy)     AS avg_tachy_events,
    AVG(cnt_hypotn)    AS avg_hypotn_events,
    AVG(cnt_tachypnea) AS avg_tachypnea_events,
    AVG(los)           AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate
  FROM tagged
  GROUP BY quartile_grp
)

-- 9. Final output: p99 + metrics table
SELECT
  p.p99 AS composite_score_99th_pct,
  m.quartile_grp,
  m.n_stays,
  m.avg_tachy_events,
  m.avg_hypotn_events,
  m.avg_tachypnea_events,
  m.avg_icu_los,
  m.mortality_rate
FROM percentiles p
LEFT JOIN metrics m
  ON m.quartile_grp IN ('top_quartile', 'other')
ORDER BY
  CASE WHEN m.quartile_grp='top_quartile' THEN 1 ELSE 2 END;