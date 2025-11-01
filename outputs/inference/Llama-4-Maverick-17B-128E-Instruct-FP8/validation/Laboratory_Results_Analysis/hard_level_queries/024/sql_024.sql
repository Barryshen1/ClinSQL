WITH 
-- Step 1 & 2: Filter patients based on age, gender, and condition (post-cardiac arrest)
eligible_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.dischtime, a.admittime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code IN ('I46.0', 'I46.2', 'I46.8', 'I46.9')  -- ICD codes for cardiac arrest
    )
),

-- Step 3: Calculate 48-hour lab instability score
lab_instability_score AS (
  SELECT ep.hadm_id, 
         PERCENTILE_CONT(ABS(LE.valuenum - DLI.ref_range_lower) / (DLI.ref_range_upper - DLI.ref_range_lower)) OVER (PARTITION BY ep.hadm_id) AS instability_score
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` LE ON ep.hadm_id = LE.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` DLI ON LE.itemid = DLI.itemid
  WHERE LE.charttime BETWEEN TIMESTAMP_SUB(ep.dischtime, INTERVAL 48 HOUR) AND ep.dischtime
    AND DLI.ref_range_lower IS NOT NULL AND DLI.ref_range_upper IS NOT NULL
),

-- Calculate 90th percentile of the instability score
percentile_90 AS (
  SELECT PERCENTILE_CONT(instability_score, 0.9) AS threshold
  FROM lab_instability_score
),

-- Step 4: Patients with score >= 90th percentile
high_risk_patients AS (
  SELECT hadm_id
  FROM lab_instability_score
  WHERE instability_score >= (SELECT threshold FROM percentile_90)
),

-- Calculate required statistics for high-risk patients
stats_high_risk AS (
  SELECT 
    COUNT(DISTINCT hrp.hadm_id) AS count_high_risk,
    SUM(CASE WHEN ep.deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(DISTINCT hrp.hadm_id) AS mortality,
    AVG(TIMESTAMP_DIFF(ep.dischtime, ep.admittime, HOUR)) AS mean_los
  FROM high_risk_patients hrp
  INNER JOIN eligible_patients ep ON hrp.hadm_id = ep.hadm_id
),

-- Compare critical lab frequency
critical_lab_frequency AS (
  SELECT 
    COUNT(CASE WHEN LE.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE category = 'Critical') THEN 1 END) / COUNT(LE.labevent_id) AS freq_critical_labs_high_risk,
    (SELECT COUNT(CASE WHEN LE2.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE category = 'Critical') THEN 1 END) / COUNT(LE2.labevent_id) FROM `physionet-data.mimiciv_3_1_hosp.labevents` LE2) AS freq_critical_labs_all
  FROM high_risk_patients hrp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` LE ON hrp.hadm_id = LE.hadm_id
)

-- Final output
SELECT 
  (SELECT threshold FROM percentile_90) AS percentile_90_threshold,
  (SELECT count_high_risk FROM stats_high_risk) AS count_high_risk,
  (SELECT mortality FROM stats_high_risk) AS mortality_high_risk,
  (SELECT mean_los FROM stats_high_risk) AS mean_los_high_risk,
  (SELECT freq_critical_labs_high_risk FROM critical_lab_frequency) AS freq_critical_labs_high_risk,
  (SELECT freq_critical_labs_all FROM critical_lab_frequency) AS freq_critical_labs_all;