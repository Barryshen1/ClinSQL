WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(did.long_title) LIKE '%sepsis%'
    AND LOWER(did.long_title) LIKE '%septic%'
),

critical_lab_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) IN (
    'lactate', 'creatinine', 'wbc', 'platelets', 'ph', 'base excess', 'bicarbonate', 
    'potassium', 'sodium', 'glucose', 'anion gap', 'chloride', 'calcium', 'magnesium', 
    'phosphate', 'bilirubin', 'alt', 'ast', 'pt', 'ptt', 'inr', 'lactic acid',
    'blood culture', 'c-reactive protein', 'procalcitonin', 'albumin', 'total protein'
  )
),

critical_lab_events AS (
  SELECT 
    le.hadm_id,
    COUNT(*) AS critical_event_count
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN sepsis_admissions sa ON le.hadm_id = sa.hadm_id
  JOIN critical_lab_items cli ON le.itemid = cli.itemid
  WHERE le.charttime >= sa.admittime
    AND le.charttime <= TIMESTAMP_ADD(sa.admittime, INTERVAL 72 HOUR)
    AND (le.flag = 'Abnormal' 
         OR (le.valuenum IS NOT NULL 
             AND le.ref_range_lower IS NOT NULL 
             AND le.ref_range_upper IS NOT NULL 
             AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)))
  GROUP BY le.hadm_id
)

SELECT 
  COUNT(sa.hadm_id) AS cohort_size,
  AVG(COALESCE(cle.critical_event_count, 0)) AS mean_critical_events_per_admission,
  PERCENTILE_CONT(COALESCE(cle.critical_event_count, 0), 0.25) AS p25_critical_events,
  AVG(sa.los) AS mean_los_days,
  AVG(CAST(sa.hospital_expire_flag AS FLOAT)) AS mortality_rate
FROM sepsis_admissions sa
LEFT JOIN critical_lab_events cle ON sa.hadm_id = cle.hadm_id;