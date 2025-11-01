WITH sepsis_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '038.%' OR icd_code = '785.52'))
     OR (icd_version = 10 AND (icd_code LIKE 'A41.%' OR icd_code LIKE 'R65.2%'))
),
abnormal_labs AS (
  SELECT 
    le.hadm_id,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.hadm_id = a.hadm_id
  WHERE le.flag = 'abnormal'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY le.hadm_id
)
SELECT 
  COUNT(*) AS cohort_size,
  AVG(COALESCE(al.lab_count, 0)) AS mean_critical_events_per_admission,
  APPROX_QUANTILES(COALESCE(al.lab_count, 0), 4)[OFFSET(1)] AS p25_instability_score,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_los_days,
  AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
JOIN sepsis_hadm s ON a.hadm_id = s.hadm_id
LEFT JOIN abnormal_labs al ON a.hadm_id = al.hadm_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 43 AND 53;