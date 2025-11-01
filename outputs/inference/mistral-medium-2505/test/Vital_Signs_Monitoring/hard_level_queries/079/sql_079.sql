WITH
-- Get male patients aged 81-91
patient_demo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 81 AND 91
),

-- Get ICU stays with first 48 hours
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    s.los AS icu_los,
    TIMESTAMP_DIFF(s.outtime, s.intime, DAY) AS icu_los_days,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  WHERE
    s.subject_id IN (SELECT subject_id FROM patient_demo)
),

-- Identify HFNC use in first 48 hours
hfnc_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.icu_intime
  FROM
    icu_stays i
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    i.subject_id = ce.subject_id AND i.hadm_id = ce.hadm_id AND i.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    -- HFNC-related itemids (example - adjust based on actual MIMIC-IV codes)
    di.label LIKE '%High Flow Nasal Cannula%'
    OR di.label LIKE '%HFNC%'
    OR di.label LIKE '%Optiflow%'
    -- Within first 48 hours
    AND TIMESTAMP_DIFF(ce.charttime, i.icu_intime, HOUR) <= 48
),

-- Calculate composite instability score (example components - adjust as needed)
instability_scores AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.stay_id,
    -- Example score calculation (adjust based on actual clinical definition)
    -- This is a placeholder - you would need to define the actual components
    -- and their weights for the composite score
    GREATEST(
      IFNULL(MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum ELSE NULL END), 0) * 0.1 +
      IFNULL(MAX(CASE WHEN di.label = 'Respiratory Rate' THEN ce.valuenum ELSE NULL END), 0) * 0.2 +
      IFNULL(MAX(CASE WHEN di.label = 'SpO2' THEN 100 - ce.valuenum ELSE NULL END), 0) * 0.3 +
      IFNULL(MAX(CASE WHEN di.label = 'Systolic Blood Pressure' THEN 120 - ce.valuenum ELSE NULL END), 0) * 0.4,
      0
    ) AS composite_score
  FROM
    hfnc_patients h
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    h.subject_id = ce.subject_id AND h.hadm_id = ce.hadm_id AND h.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    -- Within first 48 hours
    TIMESTAMP_DIFF(ce.charttime, h.icu_intime, HOUR) <= 48
    -- Example vital signs (adjust based on actual clinical definition)
    AND di.category IN ('Vital Signs', 'Respiratory')
  GROUP BY
    h.subject_id, h.hadm_id, h.stay_id
),

-- Calculate percentiles
percentiles AS (
  SELECT
    composite_score,
    PERCENT_RANK() OVER (ORDER BY composite_score) AS percentile
  FROM
    instability_scores
),

-- Get top decile metrics
top_decile AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.icu_los_days,
    i.hospital_expire_flag,
    s.composite_score
  FROM
    icu_stays i
  JOIN
    instability_scores s
  ON
    i.subject_id = s.subject_id AND i.hadm_id = s.hadm_id AND i.stay_id = s.stay_id
  WHERE
    s.composite_score >= (
      SELECT MIN(composite_score)
      FROM percentiles
      WHERE percentile >= 0.9
    )
)

-- Final results
SELECT
  -- Percentile for score of 85
  (SELECT percentile FROM percentiles WHERE composite_score = 85) AS percentile_for_85,

  -- Average ICU LOS for top decile
  AVG(icu_los_days) AS avg_icu_los_top_decile,

  -- Hospital mortality percentage for top decile
  100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS hospital_mortality_pct_top_decile

FROM
  top_decile;