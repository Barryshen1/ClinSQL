WITH 
-- Step 1: Filter the population
cohort AS (
  SELECT p.subject_id, p.anchor_year, a.hadm_id, a.admittime, a.dischtime, a.admission_type, a.hospital_expire_flag,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 52 AND 62
),

-- Step 2 & 3: Identify sepsis, calculate comorbidity count
sepsis_cohort AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.admission_type, c.los_days, c.hospital_expire_flag,
         -- Simplified sepsis identification using ICD codes
         MAX(CASE WHEN d.icd_code IN ('R65.20', 'R65.21') THEN 1 ELSE 0 END) AS has_sepsis,
         MAX(CASE WHEN d.icd_code = 'R65.21' THEN 1 ELSE 0 END) AS has_septic_shock,
         COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON c.hadm_id = d.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.admission_type, c.los_days, c.hospital_expire_flag
),

-- Step 4: Stratify and calculate outcomes
stratified_outcomes AS (
  SELECT 
    CASE 
      WHEN has_septic_shock = 1 THEN 'Septic Shock'
      WHEN has_sepsis = 1 THEN 'Sepsis without Shock'
      ELSE 'No Sepsis'
    END AS sepsis_severity,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE '<1'
    END AS los_category,
    admission_type,
    AVG(comorbidity_count) AS mean_comorbidity_count,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct
  FROM sepsis_cohort
  WHERE has_sepsis = 1  -- Only consider patients with sepsis
  GROUP BY 
    CASE 
      WHEN has_septic_shock = 1 THEN 'Septic Shock'
      WHEN has_sepsis = 1 THEN 'Sepsis without Shock'
      ELSE 'No Sepsis'
    END,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE '<1'
    END,
    admission_type
)

SELECT * FROM stratified_outcomes
ORDER BY sepsis_severity, los_category, admission_type;