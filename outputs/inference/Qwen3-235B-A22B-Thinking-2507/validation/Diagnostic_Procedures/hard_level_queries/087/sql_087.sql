with intracranial hemorrhage (ICH) diagnosis
WITH ich_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    -- ICD-9 codes for intracranial hemorrhage: 430, 431, 432
    (icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'))
    OR
    -- ICD-10 codes for intracranial hemorrhage: I60, I61, I62
    (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),

-- Filter for female patients aged 56-66 with ICH
target_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    -- Calculate age at admission: anchor_age + (admission year - anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN ich_admissions i
    ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 56 AND 66
),

-- Link to ICU stays
icu_stays_target AS (
  SELECT 
    tp.hadm_id,
    tp.subject_id,
    icu.stay_id,
    icu.intime
  FROM target_population tp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON tp.hadm_id = icu.hadm_id AND tp.subject_id = icu.subject_id
),

-- Count lab events in first 72 hours for each ICU stay
lab_events_count AS (
  SELECT 
    icu.stay_id,
    COUNT(l.labevent_id) AS lab_event_count
  FROM icu_stays_target icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON icu.hadm_id = l.hadm_id
    AND l.charttime >= icu.intime
    AND l.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY icu.stay_id
),

-- Calculate diagnostic intensity (events per hour)
diagnostic_intensity AS (
  SELECT 
    stay_id,
    lab_event_count / 72.0 AS diagnostic_intensity
  FROM lab_events_count
)

-- Calculate 95th percentile of diagnostic intensity
SELECT 
  APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(95)] AS pct95_diagnostic_intensity
FROM diagnostic_intensity;