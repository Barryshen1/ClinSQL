WITH 
  -- Identify sepsis patients
  sepsis_patients AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN ('995.91', '998.0', 'A41.9', 'R65.20', 'R65.21')
  ),
  
  -- Male patients aged 90-100
  target_patients AS (
    SELECT subject_id, anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 90 AND 100
  ),
  
  -- ICU stays for target patients with sepsis
  icu_stays AS (
    SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN target_patients tp ON i.subject_id = tp.subject_id
    JOIN sepsis_patients sp ON i.hadm_id = sp.hadm_id
  ),
  
  -- Diagnostic utilization in first 24h
  diagnostic_utilization AS (
    SELECT 
      iu.stay_id,
      COUNT(DISTINCT CASE 
        WHEN ce.charttime BETWEEN iu.intime AND TIMESTAMP_ADD(iu.intime, INTERVAL 24 HOUR) THEN ce.itemid 
      END) AS diag_utilization
    FROM icu_stays iu
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON iu.stay_id = ce.stay_id
    GROUP BY iu.stay_id
  )

SELECT 
  -- Calculate SD, p75, p95 of diagnostic utilization
  STDDEV(diag_utilization) AS sd_diag_utilization,
  APPROX_QUANTILES(diag_utilization, 0.75)[OFFSET(1)] AS p75_diag_utilization,
  APPROX_QUANTILES(diag_utilization, 0.95)[OFFSET(1)] AS p95_diag_utilization,
  
  -- In-hospital mortality percentage
  SUM(CASE 
    WHEN a.hospital_expire_flag = 1 THEN 1 
    ELSE 0 
  END) / COUNT(DISTINCT iu.hadm_id) * 100 AS in_hospital_mortality_pct,
  
  -- Average LOS in ICU
  AVG(TIMESTAMP_DIFF(iu.outtime, iu.intime, HOUR)) / 24 AS avg_icu_los,
  
  -- Admissions versus overall ICU
  COUNT(DISTINCT iu.hadm_id) AS admissions,
  (SELECT COUNT(DISTINCT stay_id) FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS overall_icu_admissions
FROM diagnostic_utilization du
JOIN icu_stays iu ON du.stay_id = iu.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON iu.hadm_id = a.hadm_id;