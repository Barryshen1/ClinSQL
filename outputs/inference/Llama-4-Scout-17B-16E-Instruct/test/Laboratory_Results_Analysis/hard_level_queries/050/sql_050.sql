WITH 
female_patients AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
),

ards_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.icd_code IN ('J80', 'J81')  
  AND di.subject_id IN (SELECT subject_id FROM female_patients)
),

ards_icustays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN ards_patients ap ON i.subject_id = ap.subject_id AND i.hadm_id = ap.hadm_id
),

lab_events AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id, 
    COUNT(ce.itemid) AS lab_events_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN ards_icustays ai ON ce.subject_id = ai.subject_id AND ce.hadm_id = ai.hadm_id AND ce.stay_id = ai.stay_id
  WHERE ce.charttime BETWEEN ai.intime AND TIMESTAMP_ADD(ai.intime, INTERVAL 72 HOUR)
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),

-- Non-ARDS inpatients for comparison
non_ards_patients AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
  AND p.subject_id NOT IN (SELECT subject_id FROM ards_patients)
),

non_ards_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.dischtime, a.admittime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN non_ards_patients nap ON a.subject_id = nap.subject_id
),

non_ards_icustays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN non_ards_admissions naa ON i.subject_id = naa.subject_id AND i.hadm_id = naa.hadm_id
),

non_ards_lab_events AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id, 
    COUNT(ce.itemid) AS lab_events_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN non_ards_icustays nai ON ce.subject_id = nai.subject_id AND ce.hadm_id = nai.hadm_id AND ce.stay_id = nai.stay_id
  WHERE ce.charttime BETWEEN nai.intime AND TIMESTAMP_ADD(nai.intime, INTERVAL 72 HOUR)
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),

-- Calculate 75th percentile lab instability score for ARDS patients
percentile_75 AS (
  SELECT APPROX_QUANTILES(lab_events_count, 0.75) AS ards_percentile_75
  FROM lab_events
),

ards_above_threshold AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    lab_events.lab_events_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN ards_patients ap ON a.subject_id = ap.subject_id AND a.hadm_id = ap.hadm_id
    JOIN lab_events ON a.hadm_id = lab_events.hadm_id
  WHERE lab_events.lab_events_count >= (SELECT ards_percentile_75 FROM percentile_75)[OFFSET(0)]
)

SELECT 
  -- 75th percentile lab instability score for ARDS patients
  (SELECT ards_percentile_75 FROM percentile_75)[OFFSET(0)] AS ards_percentile_75,
  -- Mortality, mean LOS for ARDS patients at/above threshold
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(hadm_id) AS ards_mortality,
  AVG(los) AS ards_mean_LOS,
  -- Average critical lab events for ARDS patients at/above threshold
  AVG(lab_events_count) AS ards_avg_lab_events,
  -- Comparison to non-ARDS
  AVG(non_ards_lab_events.lab_events_count) AS non_ards_avg_lab_events
FROM 
  ards_above_threshold
  CROSS JOIN (
    SELECT AVG(lab_events_count) AS lab_events_count
    FROM non_ards_lab_events
  ) AS non_ards_avg;