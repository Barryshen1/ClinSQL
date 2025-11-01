WITH cohort AS (
  -- Step 1: Identify female ICU patients aged 75–85
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
),

-- Step 2: Identify patients on invasive mechanical ventilation in first 48h
ventilated AS (
  SELECT DISTINCT
    ce.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  WHERE LOWER(di.label) IN ('mech vent', 'ventilator', 'ventilator mode')
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
),

-- Step 3: Extract vital signs in first 48h
vitals AS (
  SELECT
    ce.stay_id,
    MAX(CASE WHEN LOWER(di.label) LIKE '%heart rate%' THEN ce.valuenum END) AS heart_rate,
    MAX(CASE WHEN LOWER(di.label) LIKE '%mean%' AND LOWER(di.label) LIKE '%arterial%' THEN ce.valuenum END) AS map,
    MAX(CASE WHEN LOWER(di.label) LIKE '%gcs%' THEN ce.valuenum END) AS gcs,
    MAX(CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN ce.valuenum END) AS rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  WHERE ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND LOWER(di.label) IN ('heart rate', 'mean arterial pressure', 'gcs total', 'respiratory rate')
  GROUP BY ce.stay_id
),

-- Step 4: Compute instability score
instability_scores AS (
  SELECT
    v.stay_id,
    v.heart_rate,
    v.map,
    v.gcs,
    v.rr,
    (
      IF(v.heart_rate > 120, 1, 0) +
      IF(v.map < 65, 1, 0) +
      IF(v.gcs < 8, 1, 0) +
      IF(v.rr > 25 OR v.rr < 10, 1, 0)
    ) AS instability_score
  FROM vitals v
  JOIN ventilated ven
    ON v.stay_id = ven.stay_id
),

-- Step 5: Join with cohort
cohort_with_scores AS (
  SELECT
    c.*,
    i.instability_score,
    i.heart_rate,
    i.map
  FROM cohort c
  JOIN instability_scores i
    ON c.stay_id = i.stay_id
),

-- Step 6: Compute 90th percentile
percentile_90 AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS score_90th
  FROM cohort_with_scores
),

-- Step 7: Top 25% of scores
top_quartile AS (
  SELECT *
  FROM cohort_with_scores
  WHERE instability_score >= (
    SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(75)]
    FROM cohort_with_scores
  )
)

-- Final output
SELECT
  (SELECT score_90th FROM percentile_90) AS instability_score_90th_percentile,
  AVG(CASE WHEN heart_rate > 120 THEN 1 ELSE 0 END) AS prop_tachycardia,
  AVG(CASE WHEN map < 65 THEN 1 ELSE 0 END) AS prop_hypotension,
  AVG(icu_los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM top_quartile;