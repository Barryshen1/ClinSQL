WITH
-- Define lower GI bleed ICD codes (K55-K63 range)
lower_gi_bleed_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
    AND icd_code BETWEEN 'K550' AND 'K639'
),

-- Identify our cohort: women 65-75 with lower GI bleed in first 72 hours
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN lower_gi_bleed_codes lgib ON d.icd_code = lgib.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND d.seq_num = 1  -- Primary diagnosis
    AND TIMESTAMP_DIFF(d.chartdate, a.admittime, HOUR) <= 72  -- Fixed to check diagnosis time vs admission time
),

-- General inpatient comparison group (excluding our cohort)
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.hadm_id NOT IN (SELECT hadm_id FROM cohort)
),

-- Define key lab tests for instability score
key_lab_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'Hemoglobin',
    'Platelet Count',
    'Creatinine',
    'Sodium',
    'Potassium',
    'INR(PT)',
    'Lactate'
  )
),

-- Get lab values for cohort in first 72 hours
cohort_labs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    d.label,
    l.ref_range_lower,
    l.ref_range_upper
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN key_lab_items k ON l.itemid = k.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, c.admittime, HOUR) <= 72
),

-- Calculate lab instability score (simple approach: count of abnormal values)
cohort_lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNTIF(
      (valuenum < ref_range_lower OR valuenum > ref_range_upper) AND
      (ref_range_lower IS NOT NULL OR ref_range_upper IS NOT NULL)
    ) AS instability_score
  FROM cohort_labs
  GROUP BY subject_id, hadm_id
),

-- Get lab values for general inpatients in first 72 hours
general_labs AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    d.label,
    l.ref_range_lower,
    l.ref_range_upper
  FROM general_inpatients g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON g.subject_id = l.subject_id AND g.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN key_lab_items k ON l.itemid = k.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, g.admittime, HOUR) <= 72
),

-- Calculate lab instability score for general inpatients
general_lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNTIF(
      (valuenum < ref_range_lower OR valuenum > ref_range_upper) AND
      (ref_range_lower IS NOT NULL OR ref_range_upper IS NOT NULL)
    ) AS instability_score
  FROM general_labs
  GROUP BY subject_id, hadm_id
),

-- Calculate 25th percentile instability score for cohort
cohort_stats AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS p25_instability_score,
    AVG(los_hours) AS avg_los,
    SUM(CASE WHEN hospital_expire_flag = 1 OR dod IS NOT NULL THEN 1 ELSE 0 END) AS mortality_count,
    COUNT(*) AS cohort_size
  FROM cohort_lab_scores c
  JOIN cohort ON c.subject_id = cohort.subject_id AND c.hadm_id = cohort.hadm_id
),

-- Calculate critical lab event frequency for both groups
lab_event_frequency AS (
  SELECT
    'Cohort' AS group_type,
    COUNT(*) AS total_lab_events,
    COUNT(DISTINCT subject_id) AS unique_patients,
    COUNT(*) / COUNT(DISTINCT subject_id) AS events_per_patient
  FROM cohort_labs

  UNION ALL

  SELECT
    'General Inpatients' AS group_type,
    COUNT(*) AS total_lab_events,
    COUNT(DISTINCT subject_id) AS unique_patients,
    COUNT(*) / COUNT(DISTINCT subject_id) AS events_per_patient
  FROM general_labs
)

-- Final results
SELECT
  'Cohort Statistics' AS metric_type,
  p25_instability_score,
  avg_los,
  mortality_count,
  cohort_size,
  mortality_count / cohort_size AS mortality_rate
FROM cohort_stats

UNION ALL

SELECT
  'Lab Event Frequency' AS metric_type,
  NULL AS p25_instability_score,
  NULL AS avg_los,
  NULL AS mortality_count,
  NULL AS cohort_size,
  NULL AS mortality_rate
FROM lab_event_frequency

UNION ALL

SELECT
  'Lab Event Frequency Details' AS metric_type,
  group_type,
  total_lab_events,
  unique_patients,
  events_per_patient,
  NULL AS mortality_rate
FROM lab_event_frequency;