WITH sepsis_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
  ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Sepsis%' OR dicd.long_title LIKE '%septic%'
),
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id, icu.stay_id, icu.intime, icu.los, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
  AND a.hadm_id IN (SELECT hadm_id FROM sepsis_patients)
),
diagnostic_utilization AS (
  SELECT ep.stay_id, COUNT(*) AS num_events
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ep.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN ep.intime AND TIMESTAMP_ADD(ep.intime, INTERVAL 24 HOUR)
  GROUP BY ep.stay_id
)
SELECT 
  STDDEV(num_events) AS sd_diagnostic_utilization,
  APPROX_QUANTILES(num_events, 100)[OFFSET(75)] AS p75_diagnostic_utilization,
  APPROX_QUANTILES(num_events, 100)[OFFSET(95)] AS p95_diagnostic_utilization,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100 AS in_hospital_mortality_percent,
  AVG(los) AS average_los,
  COUNT(DISTINCT ep.stay_id) AS num_icu_admissions,
  (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS total_icu_admissions
FROM diagnostic_utilization du
INNER JOIN eligible_patients ep ON du.stay_id = ep.stay_id;