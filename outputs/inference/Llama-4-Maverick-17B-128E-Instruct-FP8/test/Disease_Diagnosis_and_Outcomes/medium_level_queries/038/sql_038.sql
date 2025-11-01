WITH heart_failure_patients AS (
  SELECT DISTINCT diag.subject_id, diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON diag.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 80 AND 90
  AND d_diag.long_title LIKE '%Heart failure%'
),
ckd_diabetes_patients AS (
  SELECT DISTINCT diag.subject_id, diag.hadm_id,
    MAX(CASE WHEN d_diag.long_title LIKE '%Chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d_diag.long_title LIKE '%Diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  GROUP BY diag.subject_id, diag.hadm_id
),
icu_los AS (
  SELECT a.subject_id, a.hadm_id,
    COALESCE(ic.stay_id, 0) AS had_icu_stay,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
),
mortality_outcomes AS (
  SELECT a.subject_id, a.hadm_id, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
)

SELECT 
  CASE WHEN il.had_icu_stay = 0 THEN 'Non-ICU' ELSE 'ICU' END AS icu_status,
  CASE WHEN il.los < 8 THEN '<8' ELSE '>=8' END AS los_category,
  COUNT(*) AS total_patients,
  SUM(mo.hospital_expire_flag) AS in_hospital_deaths,
  (SUM(mo.hospital_expire_flag) / COUNT(*)) * 100 AS in_hospital_mortality_percent,
  AVG(cd.has_ckd) * 100 AS ckd_prevalence,
  AVG(cd.has_diabetes) * 100 AS diabetes_prevalence
FROM heart_failure_patients hf
INNER JOIN icu_los il ON hf.hadm_id = il.hadm_id
INNER JOIN ckd_diabetes_patients cd ON hf.subject_id = cd.subject_id AND hf.hadm_id = cd.hadm_id
INNER JOIN mortality_outcomes mo ON hf.hadm_id = mo.hadm_id
GROUP BY icu_status, los_category
ORDER BY icu_status, los_category;