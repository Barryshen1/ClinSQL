WITH patient_admissions AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    a.hadm_id,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 52 AND 62
),

sepsis_codes AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code IN ('99591', '99592', '78552')) 
             OR (icd_version = 10 AND icd_code IN ('A41', 'R65.20', 'R65.21')) 
          THEN 1 ELSE 0 
        END) AS sepsis_flag,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code = '78552') 
             OR (icd_version = 10 AND icd_code = 'R65.21') 
          THEN 1 ELSE 0 
        END) AS septic_shock_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
  GROUP BY hadm_id
),

sepsis_admissions AS (
  SELECT 
    pa.*,
    sc.sepsis_flag,
    sc.septic_shock_flag
  FROM patient_admissions pa
  INNER JOIN sepsis_codes sc
    ON pa.hadm_id = sc.hadm_id
  WHERE sc.sepsis_flag = 1
),

comorbidities AS (
  SELECT 
    diag.hadm_id,
    COUNT(DISTINCT 
      CASE WHEN NOT (
        (diag.icd_version = 9 AND diag.icd_code IN ('99591', '99592', '78552')) 
        OR (diag.icd_version = 10 AND diag.icd_code IN ('A41', 'R65.20', 'R65.21'))
      ) THEN diag.icd_code ELSE NULL END
    ) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN sepsis_admissions sa
    ON diag.hadm_id = sa.hadm_id
  GROUP BY diag.hadm_id
),

combined AS (
  SELECT 
    sa.*,
    DATE_DIFF(sa.dischtime, sa.admittime, DAY) AS los_days,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count
  FROM sepsis_admissions sa
  LEFT JOIN comorbidities c
    ON sa.hadm_id = c.hadm_id
)

SELECT 
  CASE 
    WHEN septic_shock_flag = 1 THEN 'Septic Shock' 
    ELSE 'No Shock' 
  END AS sepsis_severity,
  CASE 
    WHEN los_days <= 3 THEN '1-3'  -- Includes 0-day stays
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    WHEN los_days >= 8 THEN '>=8'
  END AS los_group,
  admission_type,
  COUNT(*) AS total_admissions,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  AVG(comorbidity_count) AS mean_comorbidity_count
FROM combined
GROUP BY sepsis_severity, los_group, admission_type
ORDER BY sepsis_severity, los_group, admission_type;