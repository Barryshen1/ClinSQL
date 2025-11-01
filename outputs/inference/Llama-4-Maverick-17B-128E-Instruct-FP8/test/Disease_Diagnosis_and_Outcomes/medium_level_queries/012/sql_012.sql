WITH heart_failure_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 83 AND 93
  AND dicd.long_title LIKE '%Heart failure%'
),
icu_stays AS (
  SELECT hadm_id, COUNT(stay_id) AS icu_stay_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
comorbidities AS (
  SELECT d.hadm_id, COUNT(DISTINCT dicd.icd_code) AS comorbidity_count,
         SUM(CASE WHEN dicd.long_title LIKE '%Diabetes%' THEN 1 ELSE 0 END) AS diabetes_count,
         SUM(CASE WHEN dicd.long_title LIKE '%Chronic kidney disease%' THEN 1 ELSE 0 END) AS ckd_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  GROUP BY d.hadm_id
),
patient_data AS (
  SELECT hf.subject_id, hf.hadm_id, hf.anchor_age,
         a.admittime, a.dischtime, a.hospital_expire_flag,
         COALESCE(icu.icu_stay_count, 0) > 0 AS icu_stay,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
         COALESCE(com.comorbidity_count, 0) AS comorbidity_count,
         COALESCE(com.diabetes_count, 0) > 0 AS diabetes,
         COALESCE(com.ckd_count, 0) > 0 AS ckd
  FROM heart_failure_patients hf
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON hf.hadm_id = a.hadm_id
  LEFT JOIN icu_stays icu ON hf.hadm_id = icu.hadm_id
  LEFT JOIN comorbidities com ON hf.hadm_id = com.hadm_id
)
SELECT 
  icu_stay,
  los < 8 AS los_stratum,
  CASE 
    WHEN comorbidity_count <= 1 THEN '0-1'
    WHEN comorbidity_count = 2 THEN '2'
    ELSE '>=3'
  END AS comorbidity_stratum,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) / COUNT(*) * 100 AS mortality_percent,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  SUM(CASE WHEN diabetes THEN 1 ELSE 0 END) / COUNT(*) * 100 AS diabetes_prevalence,
  SUM(CASE WHEN ckd THEN 1 ELSE 0 END) / COUNT(*) * 100 AS ckd_prevalence
FROM patient_data
GROUP BY icu_stay, los_stratum, comorbidity_stratum
ORDER BY icu_stay, los_stratum, comorbidity_stratum;