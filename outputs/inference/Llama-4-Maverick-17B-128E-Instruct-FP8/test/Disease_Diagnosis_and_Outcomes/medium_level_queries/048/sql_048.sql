WITH 
cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 68 AND 78
),
diagnoses AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN d.long_title LIKE '%Chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.long_title LIKE '%Diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY 
    hadm_id
)
SELECT 
  CASE WHEN c.los < 8 THEN '<8 days' ELSE '>=8 days' END AS los_category,
  COUNT(*) AS total_patients,
  SUM(c.hospital_expire_flag) / COUNT(*) * 100 AS in_hospital_mortality,
  SUM(d.has_ckd) / COUNT(*) * 100 AS ckd_prevalence,
  SUM(d.has_diabetes) / COUNT(*) * 100 AS diabetes_prevalence
FROM 
  cohort c
INNER JOIN 
  diagnoses d ON c.hadm_id = d.hadm_id
GROUP BY 
  CASE WHEN c.los < 8 THEN '<8 days' ELSE '>=8 days' END
ORDER BY 
  los_category;