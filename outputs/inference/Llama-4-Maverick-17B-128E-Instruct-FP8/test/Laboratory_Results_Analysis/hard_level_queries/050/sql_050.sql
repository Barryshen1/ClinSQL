WITH 
-- Step 1: Identify ARDS patients aged 40-50, female
ARDS_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
  AND d_diag.long_title LIKE '%Acute respiratory distress syndrome%'
),

-- Step 2: Calculate laboratory-instability score for the first 72 hours in ICU
lab_instability AS (
  SELECT icu.stay_id, 
         COUNT(CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1 END) AS lab_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN ARDS_patients ON icu.hadm_id = ARDS_patients.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON icu.hadm_id = le.hadm_id
  WHERE DATETIME_DIFF(le.charttime, icu.intime, HOUR) <= 72
  GROUP BY icu.stay_id
),

-- Step 3: Calculate 75th percentile of lab_instability score
percentile_75 AS (
  SELECT APPROX_QUANTILES(lab_score, 100)[OFFSET(75)] AS threshold
  FROM lab_instability
),

-- Step 4: Analyze outcomes for patients at/above threshold vs. non-ARDS
outcomes AS (
  SELECT 
    CASE WHEN li.lab_score >= (SELECT threshold FROM percentile_75) THEN 'Above Threshold' ELSE 'Below Threshold' END AS threshold_group,
    a.hospital_expire_flag AS mortality,
    icu.los,
    COUNT(le.labevent_id) AS critical_lab_events
  FROM ARDS_patients ap
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ap.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ap.hadm_id = icu.hadm_id
  JOIN lab_instability li ON icu.stay_id = li.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON icu.hadm_id = le.hadm_id AND DATETIME_DIFF(le.charttime, icu.intime, HOUR) <= 72
  GROUP BY li.lab_score, a.hospital_expire_flag, icu.los
),

-- Non-ARDS cohort for comparison
non_ards_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
  AND (d_diag.long_title NOT LIKE '%Acute respiratory distress syndrome%' OR d_diag.long_title IS NULL)
),

non_ards_lab_events AS (
  SELECT icu.stay_id, COUNT(le.labevent_id) AS critical_lab_events
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN non_ards_patients nap ON icu.hadm_id = nap.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON icu.hadm_id = le.hadm_id AND DATETIME_DIFF(le.charttime, icu.intime, HOUR) <= 72
  GROUP BY icu.stay_id
)

-- Final query to report outcomes
SELECT 
  threshold_group,
  COUNT(CASE WHEN mortality = 1 THEN 1 END) / COUNT(*) AS mortality_rate,
  AVG(los) AS mean_los,
  AVG(critical_lab_events) AS avg_critical_lab_events
FROM outcomes
GROUP BY threshold_group

UNION ALL

SELECT 
  'Non-ARDS' AS threshold_group,
  NULL AS mortality_rate,
  NULL AS mean_los,
  AVG(critical_lab_events) AS avg_critical_lab_events
FROM non_ards_lab_events;