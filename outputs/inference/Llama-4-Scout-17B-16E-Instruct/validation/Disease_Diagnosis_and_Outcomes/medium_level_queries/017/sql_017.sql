WITH 
  -- Define sepsis and septic shock ICD codes
  sepsis_icd9 AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE icd_version = 9 AND long_title IN ('Sepsis', 'Septicemia')
  ),
  sepsis_icd10 AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE icd_version = 10 AND long_title IN ('Severe sepsis', 'Sepsis')
  ),
  septic_shock_icd9 AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE icd_version = 9 AND long_title IN ('Septic shock')
  ),
  septic_shock_icd10 AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE icd_version = 10 AND long_title IN ('Septic shock')
  ),

  -- Identify sepsis cases (excluding septic shock)
  sepsis_patients AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 50 AND 60
    AND (di.icd_code IN (SELECT icd_code FROM sepsis_icd9) 
         OR di.icd_code IN (SELECT icd_code FROM sepsis_icd10))
    AND di.icd_code NOT IN (SELECT icd_code FROM septic_shock_icd9)
    AND di.icd_code NOT IN (SELECT icd_code FROM septic_shock_icd10)
  ),

  -- Calculate in-hospital mortality and time-to-death
  outcomes AS (
    SELECT 
      sp.hadm_id,
      CASE 
        WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1 
        ELSE 0 
      END AS died,
      DATE_DIFF(a.deathtime, a.admittime) AS time_to_death
    FROM sepsis_patients sp
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON sp.hadm_id = a.hadm_id
  ),

  -- Stratify by LOS
  los_stratification AS (
    SELECT 
      o.hadm_id,
      o.died,
      o.time_to_death,
      CASE 
        WHEN i.los < 8 THEN '<8'
        ELSE '≥8'
      END AS los_category
    FROM outcomes o
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON o.hadm_id = i.hadm_id
  )

-- Final calculations
SELECT 
  ls.los_category,
  AVG(ls.died) AS mortality_rate,
  APPROX_QUANTILES(ls.time_to_death, 0.5)[OFFSET(1)] AS median_time_to_death,
  AVG(ls.died) - 1.96 * SQRT(AVG(ls.died) * (1 - AVG(ls.died)) / COUNT(ls.died)) AS ci_lower,
  AVG(ls.died) + 1.96 * SQRT(AVG(ls.died) * (1 - AVG(ls.died)) / COUNT(ls.died)) AS ci_upper
FROM los_stratification ls
GROUP BY ls.los_category;