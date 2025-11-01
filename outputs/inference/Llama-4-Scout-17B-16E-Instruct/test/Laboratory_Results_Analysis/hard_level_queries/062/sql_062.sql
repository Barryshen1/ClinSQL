WITH 
-- Identify sepsis admissions
sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (d.icd_code LIKE '995.92'  -- Sepsis ICD-9 code
         OR d.icd_code LIKE 'R65.1%'  -- Systemic inflammatory response syndrome ICD-10 code
         OR d.icd_code LIKE 'A41.%')  -- Sepsis ICD-10 code
),

-- Calculate critical lab events in the first 72 hours
critical_events AS (
  SELECT 
    a.hadm_id,
    COUNT(DISTINCT CASE 
      WHEN le.valuenum IS NOT NULL AND 
           (le.valueuom = 'mg/dL' OR le.valueuom = 'mmHg') THEN le.itemid 
      END) AS critical_lab_events
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.hadm_id = le.hadm_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.hadm_id
),

-- Calculate general statistics
admission_stats AS (
  SELECT 
    a.hadm_id,
    icu.stay_id,
    a.admittime,
    a.dischtime,
    p.dod,
    COALESCE(ic.stay_id, 0) AS icu_stay_count,
    COALESCE(ce.critical_lab_events, 0) AS critical_lab_events,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  LEFT JOIN critical_events ce ON a.hadm_id = ce.hadm_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
)

-- Final calculations
SELECT 
  APPROX_QUANTILES(critical_lab_events, 0.25) OVER () AS percentile_25_critical_events,
  AVG(critical_lab_events) AS mean_critical_events,
  AVG(los) AS mean_los,
  SUM(CASE WHEN dod IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM admission_stats;