WITH sepsis_patients AS (
  SELECT DISTINCT h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON h.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Sepsis%' AND h.subject_id IN (
    SELECT subject_id FROM `physionet-data.mimiciv_3_1_hosp.patients` WHERE gender = 'M' AND anchor_age BETWEEN 50 AND 60
  )
),
icu_data AS (
  SELECT i.hadm_id, i.intime, i.outtime, 
         CASE WHEN TIMESTAMP_DIFF(i.intime, a.admittime, HOUR) <= 24 THEN 'ICU on day 1' ELSE 'Not ICU on day 1' END AS icu_day1_status
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
mortality_los AS (
  SELECT a.hadm_id, 
         CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hospital_mortality,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
)
SELECT 
  i.icu_day1_status,
  CASE WHEN ml.hospital_los <= 7 THEN 'LOS <= 7' ELSE 'LOS > 7' END AS los_category,
  COUNT(*) AS total_patients,
  SUM(ml.in_hospital_mortality) / COUNT(*) * 100 AS in_hospital_mortality_percent,
  APPROX_QUANTILES(ml.hospital_los, 100)[OFFSET(50)] AS median_los
FROM sepsis_patients sp
INNER JOIN icu_data i ON sp.hadm_id = i.hadm_id
INNER JOIN mortality_los ml ON sp.hadm_id = ml.hadm_id
GROUP BY i.icu_day1_status, los_category
ORDER BY i.icu_day1_status, los_category;