WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    -- Compute age at admission: approximate using anchor_year and anchor_age
    TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 75 AND 85
),
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    c.admittime,
    c.hospital_expire_flag,
    c.age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN cohort_admissions c
    ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
),
ventilation_check AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    MAX(CASE WHEN ce.itemid = 720 AND ce.value = '1' THEN 1 ELSE 0 END) AS has_ventilation
  FROM icu_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON s.subject_id = ce.subject_id
    AND s.hadm_id = ce.hadm_id
    AND s.stay_id = ce.stay_id
    AND ce.charttime BETWEEN s.intime AND s.outtime
    AND ce.itemid = 720
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
),
vital_signs AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    ce.itemid,
    ce.valuenum,
    ce.charttime
  FROM icu_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON s.subject_id = ce.subject_id
    AND s.hadm_id = ce.hadm_id
    AND s.stay_id = ce.stay_id
    AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (442084, 442083) -- systolic BP and heart rate
),
instability_metrics AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.los,
    s.hospital_expire_flag,
    -- Count events for hypotension and tachycardia
    COUNT(CASE WHEN v.itemid = 442084 AND v.valuenum < 90 THEN 1 END) AS hypotension_count,
    COUNT(CASE WHEN v.itemid = 442083 AND v.valuenum > 100 THEN 1 END) AS tachycardia_count,
    COUNT(CASE WHEN v.itemid = 442084 THEN 1 END) AS total_sbp_events,
    COUNT(CASE WHEN v.itemid = 442083 THEN 1 END) AS total_hr_events
  FROM icu_stays s
  LEFT JOIN vital_signs v
    ON s.subject_id = v.subject_id
    AND s.hadm_id = v.hadm_id
    AND s.stay_id = v.stay_id
  GROUP BY s.subject_id, s.hadm_id, s.stay_id, s.intime, s.los, s.hospital_expire_flag
),
icu_stays_with_metrics AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.hypotension_count,
    m.tachycardia_count,
    m.total_sbp_events,
    m.total_hr_events,
    m.los,
    m.hospital_expire_flag,
    -- Compute instability score: events per hour over 48 hours
    (m.hypotension_count + m.tachycardia_count) / 48.0 AS instability_score,
    -- Percentage of events that are hypotensive
    IF(m.total_sbp_events > 0, (m.hypotension_count * 100.0) / m.total_sbp_events, NULL) AS pct_hypotension,
    -- Percentage of events that are tachycardic
    IF(m.total_hr_events > 0, (m.tachycardia_count * 100.0) / m.total_hr_events, NULL) AS pct_tachycardia,
    -- ICU LOS in days
    m.los / 24.0 AS icu_los_days,
    -- Mortality: 1 if died during hospitalization, else 0
    CAST(m.hospital_expire_flag AS INT) AS mortality
  FROM instability_metrics m
  -- Join with ventilation_check to ensure ventilation
  INNER JOIN ventilation_check v
    ON m.subject_id = v.subject_id
    AND m.hadm_id = v.hadm_id
    AND m.stay_id = v.stay_id
    AND v.has_ventilation = 1
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100) AS pcts
  FROM icu_stays_with_metrics
),
top25_group AS (
  SELECT
    *
  FROM icu_stays_with_metrics
  WHERE instability_score >= (SELECT pcts[OFFSET(75)] FROM percentiles)
)

-- Output the 90th percentile
SELECT 
  '90th_percentile_instability_score' AS metric,
  (SELECT pcts[OFFSET(90)] FROM percentiles) AS value,
  NULL AS subject_id,
  NULL AS hadm_id,
  NULL AS stay_id,
  NULL AS instability_score,
  NULL AS pct_hypotension,
  NULL AS pct_tachycardia,
  NULL AS icu_los_days,
  NULL AS mortality

UNION ALL

-- Output the top 25% group
SELECT 
  'top25_group' AS metric,
  NULL AS value,
  subject_id,
  hadm_id,
  stay_id,
  instability_score,
  pct_hypotension,
  pct_tachycardia,
  icu_los_days,
  mortality
FROM top25_group;