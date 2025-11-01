WITH
-- Define asthma exacerbation ICD codes (J45.901, J45.902, J45.990, J45.991, J45.998)
asthma_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('J45901', 'J45902', 'J45990', 'J45991', 'J45998')
),

-- Get female patients aged 39-49 with asthma exacerbation
cohort_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN asthma_codes ac ON d.icd_code = ac.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
),

-- Get all admissions for our cohort
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort_patients cp ON a.subject_id = cp.subject_id
),

-- Get all admissions for comparison (all inpatients)
all_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- Define critical lab items (example: glucose, potassium, sodium, etc.)
critical_lab_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'Glucose', 'Potassium', 'Sodium', 'White Blood Cells',
    'Hemoglobin', 'Platelet Count', 'INR(PT)', 'PTT'
  )
),

-- Get critical lab events within first 48 hours for cohort
cohort_lab_events AS (
  SELECT l.subject_id, l.hadm_id, l.itemid, l.charttime, l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cohort_admissions ca ON l.subject_id = ca.subject_id AND l.hadm_id = ca.hadm_id
  JOIN critical_lab_items cli ON l.itemid = cli.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, ca.admittime, HOUR) <= 48
),

-- Get critical lab events for all inpatients (for comparison)
all_lab_events AS (
  SELECT l.subject_id, l.hadm_id, l.itemid, l.charttime, l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN all_admissions aa ON l.subject_id = aa.subject_id AND l.hadm_id = aa.hadm_id
  JOIN critical_lab_items cli ON l.itemid = cli.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, aa.admittime, HOUR) <= 48
),

-- Calculate lab instability score (count of abnormal values per admission) for cohort
cohort_lab_scores AS (
  SELECT
    hadm_id,
    COUNT(CASE WHEN
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Glucose') AND (valuenum < 70 OR valuenum > 180)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Potassium') AND (valuenum < 3.5 OR valuenum > 5.0)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Sodium') AND (valuenum < 135 OR valuenum > 145)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'White Blood Cells') AND (valuenum < 4.0 OR valuenum > 11.0)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Hemoglobin') AND (valuenum < 12.0)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Platelet Count') AND (valuenum < 150 OR valuenum > 400)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'INR(PT)') AND (valuenum > 1.1)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'PTT') AND (valuenum > 35))
    THEN 1 END) AS lab_instability_score
  FROM cohort_lab_events
  GROUP BY hadm_id
),

-- Calculate lab instability score for all inpatients
all_lab_scores AS (
  SELECT
    hadm_id,
    COUNT(CASE WHEN
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Glucose') AND (valuenum < 70 OR valuenum > 180)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Potassium') AND (valuenum < 3.5 OR valuenum > 5.0)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Sodium') AND (valuenum < 135 OR valuenum > 145)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'White Blood Cells') AND (valuenum < 4.0 OR valuenum > 11.0)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Hemoglobin') AND (valuenum < 12.0)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'Platelet Count') AND (valuenum < 150 OR valuenum > 400)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'INR(PT)') AND (valuenum > 1.1)) OR
      (itemid IN (SELECT itemid FROM critical_lab_items WHERE label = 'PTT') AND (valuenum > 35))
    THEN 1 END) AS lab_instability_score
  FROM all_lab_events
  GROUP BY hadm_id
),

-- Count critical lab events per admission for both groups
cohort_lab_counts AS (
  SELECT hadm_id, COUNT(*) AS critical_lab_events
  FROM cohort_lab_events
  GROUP BY hadm_id
),

all_lab_counts AS (
  SELECT hadm_id, COUNT(*) AS critical_lab_events
  FROM all_lab_events
  GROUP BY hadm_id
),

-- Calculate 75th percentile lab instability score for cohort
cohort_percentile AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.75) AS cohort_75th_percentile_lab_score
  FROM cohort_lab_scores
)

-- Final results
SELECT
  cp.cohort_75th_percentile_lab_score,
  AVG(CASE WHEN ca.hadm_id IS NOT NULL THEN clc.critical_lab_events END) AS avg_critical_labs_cohort,
  AVG(CASE WHEN aa.hadm_id IS NOT NULL THEN alc.critical_lab_events END) AS avg_critical_labs_all,
  AVG(ca.los_hours) AS avg_los_hours_cohort,
  AVG(aa.los_hours) AS avg_los_hours_all,
  AVG(ca.hospital_expire_flag) AS mortality_rate_cohort,
  AVG(aa.hospital_expire_flag) AS mortality_rate_all
FROM cohort_percentile cp
CROSS JOIN (SELECT 1 AS dummy) d
LEFT JOIN cohort_admissions ca ON 1=1
LEFT JOIN all_admissions aa ON 1=1
LEFT JOIN cohort_lab_counts clc ON ca.hadm_id = clc.hadm_id
LEFT JOIN all_lab_counts alc ON aa.hadm_id = alc.hadm_id
GROUP BY cp.cohort_75th_percentile_lab_score;