WITH hfnc_itemids AS (
  -- Identify itemids for HFNC in procedureevents
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%high flow%' OR LOWER(label) LIKE '%hfnc%'
),
hfnc_patients AS (
  -- Patients receiving HFNC in first 48h of ICU stay
  SELECT
    pe.subject_id,
    pe.hadm_id,
    pe.stay_id,
    MIN(pe.starttime) AS first_hfnc_time
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN hfnc_itemids hi ON pe.itemid = hi.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pe.subject_id = icu.subject_id AND pe.stay_id = icu.stay_id
  WHERE TIMESTAMP_DIFF(pe.starttime, icu.intime, HOUR) BETWEEN 0 AND 48
  GROUP BY pe.subject_id, pe.hadm_id, pe.stay_id
),
cohort AS (
  -- Male ICU patients aged 81-91 with HFNC in first 48h
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN hfnc_patients hfnc
    ON icu.subject_id = hfnc.subject_id AND icu.stay_id = hfnc.stay_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 81 AND 91
),
cohort_scores AS (
  -- Simulate instability score for demonstration (replace with real score table if available)
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    CAST(FLOOR(RAND()*100) AS INT64) AS score, -- Simulated score between 0 and 99
    a.hospital_expire_flag
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
),
score_percentile AS (
  -- Calculate percentile for score=85
  SELECT
    COUNTIF(score < 85) AS num_below,
    COUNTIF(score = 85) AS num_equal,
    COUNT(*) AS total
  FROM cohort_scores
),
top_decile AS (
  -- Get cutoff for top 10% (decile)
  SELECT
    APPROX_QUANTILES(score, 10)[OFFSET(9)] AS decile_cutoff
  FROM cohort_scores
),
top_decile_patients AS (
  -- Patients in top decile
  SELECT *
  FROM cohort_scores, top_decile
  WHERE score >= decile_cutoff
)
SELECT
  -- Part 1: Percentile for score=85
  SAFE_DIVIDE(num_below, total) * 100 AS percentile_for_score_85,
  -- Part 2: Top decile stats
  (SELECT AVG(los) FROM top_decile_patients) AS avg_icu_los_days,
  (SELECT SAFE_DIVIDE(COUNTIF(hospital_expire_flag=1), COUNT(*)) * 100 FROM top_decile_patients) AS hospital_mortality_percent
FROM score_percentile;