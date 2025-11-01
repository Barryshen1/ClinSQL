WITH 
cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 38 AND 48
),
hf_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Heart failure%' AND d.hadm_id IN (SELECT hadm_id FROM cohort)
),
icu_status AS (
  SELECT a.hadm_id, 
         CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_admission,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM hf_patients)
),
charlson_index AS (
  SELECT d.hadm_id, COUNT(DISTINCT diag.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM hf_patients)
  GROUP BY d.hadm_id
),
combined AS (
  SELECT 
    i.hadm_id,
    i.icu_admission,
    CASE 
      WHEN i.los BETWEEN 1 AND 3 THEN '1-3'
      WHEN i.los BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_category,
    CASE 
      WHEN c.comorbidity_count <= 3 THEN '<=3'
      WHEN c.comorbidity_count BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_category,
    a.hospital_expire_flag
  FROM icu_status i
  INNER JOIN charlson_index c ON i.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
)
SELECT 
  icu_admission,
  los_category,
  charlson_category,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) / COUNT(*) * 100 AS in_hospital_mortality_pct,
  SQRT(SUM(hospital_expire_flag) / COUNT(*) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*)) * 1.96 * 100 AS mortality_ci_95,
  AVG(comorbidity_count) AS mean_comorbidity_count
FROM (
  SELECT 
    c.icu_admission,
    c.los_category,
    c.charlson_category,
    c.hospital_expire_flag,
    ci.comorbidity_count
  FROM combined c
  INNER JOIN charlson_index ci ON c.hadm_id = ci.hadm_id
) 
GROUP BY icu_admission, los_category, charlson_category
ORDER BY icu_admission, los_category, charlson_category;