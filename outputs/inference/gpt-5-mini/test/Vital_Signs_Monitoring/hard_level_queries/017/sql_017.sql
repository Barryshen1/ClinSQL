WITH icu_base AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),

hadm_asthma AS (
  -- Mark hadm_id with asthma diagnosis (ICD-9 493* or ICD-10 J45*)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '493%')
     OR (icd_version = 10 AND icd_code LIKE 'J45%')
),

cohorts AS (
  -- Label each ICU stay as 'asthma' or 'age_matched' (no asthma on same hadm_id)
  SELECT
    ib.*,
    CASE WHEN ha.hadm_id IS NOT NULL THEN 'asthma' ELSE 'age_matched' END AS cohort
  FROM icu_base ib
  LEFT JOIN hadm_asthma ha
    ON ib.hadm_id = ha.hadm_id
),

vital_events AS (
  -- Extract relevant vital measurements within first 72 hours of ICU stay
  -- Map each d_items.label to a canonical vital type
  SELECT
    c.stay_id,
    c.hadm_id,
    c.subject_id,
    di.itemid,
    LOWER(di.label) AS label,
    ce.charttime,
    ce.valuenum,
    CASE
      WHEN LOWER(di.label) LIKE '%heart rate%' THEN 'hr'
      WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN 'rr'
      WHEN LOWER(di.label) LIKE '%systolic%' THEN 'systolic'
      WHEN LOWER(di.label) LIKE '%oxygen saturation%' 
           OR LOWER(di.label) LIKE '%spo2%' 
           OR LOWER(di.label) LIKE '%o2 saturation%' THEN 'spo2'
      WHEN LOWER(di.label) LIKE '%temperature%' 
           OR LOWER(di.label) LIKE '%temp%' THEN 'temp'
      ELSE NULL
    END AS vital
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN cohorts c
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
),

vital_events_filtered AS (
  -- Keep only mapped vital types
  SELECT *
  FROM vital_events
  WHERE vital IS NOT NULL
),

per_stay_vitals AS (
  -- Aggregate per ICU stay: total relevant vital measurements and abnormal count
  SELECT
    ve.stay_id,
    c.cohort,
    COUNT(*) AS total_vitals,
    SUM(
      CASE
        WHEN ve.vital = 'hr' AND (ve.valuenum < 60 OR ve.valuenum > 100) THEN 1
        WHEN ve.vital = 'rr' AND (ve.valuenum < 12 OR ve.valuenum > 20) THEN 1
        WHEN ve.vital = 'systolic' AND (ve.valuenum < 90 OR ve.valuenum > 140) THEN 1
        WHEN ve.vital = 'spo2' AND (ve.valuenum < 92) THEN 1
        WHEN ve.vital = 'temp' AND (ve.valuenum < 36 OR ve.valuenum > 38) THEN 1
        ELSE 0
      END
    ) AS abn_count
  FROM vital_events_filtered ve
  JOIN cohorts c USING(stay_id)
  GROUP BY ve.stay_id, c.cohort
),

per_stay_scores AS (
  -- Compute instability percent per stay; exclude stays with zero relevant vitals
  SELECT
    ps.stay_id,
    ps.cohort,
    ps.total_vitals,
    ps.abn_count,
    SAFE_DIVIDE(ps.abn_count, ps.total_vitals) * 100.0 AS instability_pct,
    SAFE_DIVIDE(ps.abn_count, 72.0) AS abn_count_per_hour -- abnormal events per hour over 72h
  FROM per_stay_vitals ps
  WHERE ps.total_vitals > 0
)

-- Final summary: for each cohort, compute SD and percentiles of instability_pct,
-- plus average instability (score burden), ICU LOS and mortality.
SELECT
  s.cohort,
  COUNT(*) AS n_stays,
  -- standard deviation of instability percent across stays
  STDDEV_POP(s.instability_pct) AS instability_sd_pct,
  -- percentiles (25th, 50th, 75th, 95th) using approx quantiles
  (APPROX_QUANTILES(s.instability_pct, 100))[OFFSET(25)] AS instability_pct_25,
  (APPROX_QUANTILES(s.instability_pct, 100))[OFFSET(50)] AS instability_pct_50,
  (APPROX_QUANTILES(s.instability_pct, 100))[OFFSET(75)] AS instability_pct_75,
  (APPROX_QUANTILES(s.instability_pct, 100))[OFFSET(95)] AS instability_pct_95,
  -- mean instability percent (score burden)
  AVG(s.instability_pct) AS mean_instability_pct,
  -- mean and median ICU LOS (days) from icustays for stays included in per_stay_scores
  AVG(c.los) AS mean_icu_los_days,
  (APPROX_QUANTILES(c.los, 100))[OFFSET(50)] AS median_icu_los_days,
  -- hospital mortality rate (admissions.hospital_expire_flag is 1/0)
  AVG(c.hospital_expire_flag) AS hospital_mortality_rate
FROM per_stay_scores s
JOIN cohorts c
  ON s.stay_id = c.stay_id
GROUP BY s.cohort
ORDER BY s.cohort;