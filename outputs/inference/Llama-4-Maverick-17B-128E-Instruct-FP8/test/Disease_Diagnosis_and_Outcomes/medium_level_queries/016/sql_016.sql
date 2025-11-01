WITH ami_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE (diag.long_title LIKE '%Myocardial infarction%' AND d.icd_version = 9)
  OR (diag.long_title LIKE '%Acute myocardial infarction%' AND d.icd_version = 10)
),
cohort AS (
  SELECT p.subject_id, a.hadm_id, 
         p.gender, 
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
         a.admittime, a.dischtime, a.hospital_expire_flag,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' 
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 40 AND 50
    AND a.hadm_id IN (SELECT hadm_id FROM ami_patients)
),
icu_status AS (
  SELECT c.hadm_id, 
         MIN(DATETIME_DIFF(ic.intime, c.admittime, HOUR)) <= 24 AS icu_day1
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON c.hadm_id = ic.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  CASE WHEN c.los <= 5 THEN 'LOS <= 5' ELSE 'LOS > 5' END AS los_category,
  icu.icu_day1,
  COUNT(*) AS total_patients,
  SUM(c.hospital_expire_flag) * 100.0 / COUNT(*) AS in_hospital_mortality_pct,
  APPROX_QUANTILES(c.los, 100)[OFFSET(50)] AS median_los
FROM cohort c
JOIN icu_status icu ON c.hadm_id = icu.hadm_id
GROUP BY los_category, icu.icu_day1
ORDER BY los_category, icu.icu_day1;