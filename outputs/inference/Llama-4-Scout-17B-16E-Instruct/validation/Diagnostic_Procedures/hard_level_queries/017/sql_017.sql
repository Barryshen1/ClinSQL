WITH 
  patients_of_interest AS (
    SELECT p.subject_id, p.anchor_age, p.gender, p.dod
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 83 AND 93
  ),
  
  icu_stays AS (
    SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.first_careunit
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN patients_of_interest p ON i.subject_id = p.subject_id
    WHERE i.first_careunit IS NOT NULL  -- Ensure it's the first ICU stay
  ),
  
  sepsis_diagnosis AS (
    SELECT d.subject_id, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.icd_code IN ('995.91', '785.59', '038.0', '038.1', '038.2', '038.3', '038.4', '038.8', '038.9', 'Septicemia NOS', 'Sepsis NOS')
  ),
  
  procedures_icu AS (
    SELECT p.hadm_id, p.icd_code, p.chartdate
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN icu_stays i ON p.hadm_id = i.hadm_id
    WHERE p.chartdate BETWEEN DATE(i.intime) AND DATE_ADD(i.intime, INTERVAL 3 DAY)
  ),
  
  diagnostic_intensity AS (
    SELECT 
      s.hadm_id,
      COUNT(DISTINCT p.icd_code) AS procedure_count
    FROM icu_stays s
    JOIN procedures_icu p ON s.hadm_id = p.hadm_id
    GROUP BY s.hadm_id
  ),
  
  icu_outcomes AS (
    SELECT 
      i.hadm_id,
      TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS icu_los_days,
      CASE 
        WHEN p.dod IS NOT NULL AND p.dod <= i.outtime THEN 1 
        ELSE 0 
      END AS mortality
    FROM icu_stays i
    JOIN patients_of_interest p ON i.subject_id = p.subject_id
  ),
  
  combined AS (
    SELECT 
      di.hadm_id,
      di.procedure_count,
      io.icu_los_days,
      io.mortality
    FROM diagnostic_intensity di
    JOIN icu_outcomes io ON di.hadm_id = io.hadm_id
    JOIN sepsis_diagnosis sd ON di.hadm_id = sd.hadm_id
  )

SELECT 
  NTILE(4) OVER (ORDER BY procedure_count) AS quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(icu_los_days) AS mean_icu_los_days,
  AVG(mortality) * 100 AS mortality_percent
FROM combined
GROUP BY quartile
ORDER BY quartile;