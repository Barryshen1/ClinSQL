WITH base AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag, 
    a.admission_type,
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_adm,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE a.hadm_id IS NOT NULL
),
sepsis_comorb AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN 
      (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code = '99591' OR icd_code = '99592')) OR
      (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R65.20' OR icd_code = 'R65.21'))
      THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE WHEN 
      (icd_version = 9 AND icd_code = '78552') OR 
      (icd_version = 10 AND icd_code = 'R65.21')
      THEN 1 ELSE 0 END) AS has_shock,
    COUNT(CASE WHEN seq_num > 1 THEN 1 END) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT 
  CASE WHEN sc.has_shock = 1 THEN 'septic shock' ELSE 'no shock' END AS sepsis_severity,
  CASE 
    WHEN b.los BETWEEN 1 AND 3 THEN '1-3'
    WHEN b.los BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END AS los_group,
  b.admission_type,
  COUNT(*) AS n_admissions,
  ROUND(AVG(sc.comorb_count), 2) AS mean_comorbidity_count,
  ROUND(AVG(CASE WHEN b.hospital_expire_flag = 1 THEN 100.0 ELSE 0.0 END), 2) AS mortality_pct
FROM base b
INNER JOIN sepsis_comorb sc 
  ON b.hadm_id = sc.hadm_id
WHERE b.gender = 'M'
  AND b.age_at_adm BETWEEN 52 AND 62
  AND sc.has_sepsis = 1
  AND b.los >= 1
GROUP BY sepsis_severity, los_group, b.admission_type
ORDER BY sepsis_severity, los_group, b.admission_type;