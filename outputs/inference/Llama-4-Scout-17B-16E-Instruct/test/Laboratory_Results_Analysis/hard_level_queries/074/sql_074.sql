WITH 
-- Select target patients
target_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 37 AND 47
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE '428%'  -- Heart failure ICD code
  )
),

-- Lab events within 72 hours of admission for target patients
lab_events_target AS (
  SELECT le.hadm_id, le.itemid, le.value, le.valuenum, le.flag, le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN target_patients tp ON le.hadm_id = tp.hadm_id
  WHERE le.charttime BETWEEN tp.admittime AND TIMESTAMP_ADD(tp.admittime, INTERVAL 72 HOUR)
),

-- Calculate laboratory instability score (unique critically abnormal lab types)
lab_instability_score AS (
  SELECT hadm_id, COUNT(DISTINCT itemid) AS score
  FROM lab_events_target
  WHERE flag = 'C'  -- Critically abnormal lab flag
  GROUP BY hadm_id
),

-- General inpatients for comparison
general_inpatients AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
),

-- Lab events for general inpatients
lab_events_general AS (
  SELECT le.hadm_id, le.itemid, le.value, le.valuenum, le.flag, le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN general_inpatients gi ON le.hadm_id = gi.hadm_id
  WHERE le.charttime BETWEEN gi.admittime AND TIMESTAMP_ADD(gi.admittime, INTERVAL 72 HOUR)
),

-- Critical event rate for general inpatients
general_critical_rate AS (
  SELECT hadm_id, COUNT(DISTINCT itemid) AS general_score
  FROM lab_events_general
  WHERE flag = 'C'
  GROUP BY hadm_id
)

-- Final query
SELECT 
  'Target' AS patient_group,
  lis.hadm_id,
  lis.score AS lab_instability_score,
  TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay,
  CASE WHEN tp.dod IS NOT NULL THEN 1 ELSE 0 END AS mortality
FROM lab_instability_score lis
JOIN target_patients tp ON lis.hadm_id = tp.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON tp.hadm_id = a.hadm_id

UNION ALL

SELECT 
  'General' AS patient_group,
  gcr.hadm_id,
  gcr.general_score AS lab_instability_score,
  TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay,
  CASE WHEN gi.dod IS NOT NULL THEN 1 ELSE 0 END AS mortality
FROM general_critical_rate gcr
JOIN general_inpatients gi ON gcr.hadm_id = gi.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON gi.hadm_id = a.hadm_id;