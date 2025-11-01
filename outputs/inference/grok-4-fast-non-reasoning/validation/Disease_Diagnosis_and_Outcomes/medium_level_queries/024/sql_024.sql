WITH sepsis_codes AS (
  -- ICD-10 sepsis codes (A41.*)
  SELECT 'A41.9' AS icd_code
  UNION ALL SELECT 'A41.0'
  UNION ALL SELECT 'A41.1'
  UNION ALL SELECT 'A41.2'
  UNION ALL SELECT 'A41.3'
  UNION ALL SELECT 'A41.4'
  UNION ALL SELECT 'A41.5'
  UNION ALL SELECT 'A41.8'
  UNION ALL SELECT 'A41'
),
septic_shock_codes AS (
  -- Septic shock exclusion (R65.21*)
  SELECT 'R65.21' AS icd_code
),
ckd_codes AS (
  -- Common CKD ICD-10
  SELECT 'N18.1' AS icd_code UNION ALL SELECT 'N18.2' UNION ALL SELECT 'N18.3'
  UNION ALL SELECT 'N18.4' UNION ALL SELECT 'N18.5' UNION ALL SELECT 'N18.6'
  UNION ALL SELECT 'N18.9'
),
diabetes_codes AS (
  -- Common diabetes ICD-10 (E10*-E13*)
  SELECT 'E10' AS icd_code UNION ALL SELECT 'E11' UNION ALL SELECT 'E13'
),
sepsis_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN sepsis_codes s ON d.icd_code LIKE CONCAT(s.icd_code, '%')
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = '10'
    )
    AND NOT EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN septic_shock_codes ss ON d.icd_code LIKE CONCAT(ss.icd_code, '%')
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = '10'
    )
),
cohort_with_flags AS (
  SELECT 
    sc.*,
    DATE_DIFF(sc.dischtime, sc.admittime, DAY) AS los_days,
    CASE WHEN DATE_DIFF(sc.dischtime, sc.admittime, DAY) <= 5 THEN 'LOS <=5' ELSE 'LOS >5' END AS los_stratum,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
        WHERE t.subject_id = sc.subject_id
          AND t.hadm_id = sc.hadm_id
          AND t.eventtype = 'admit'
          AND DATE(t.intime) = DATE(sc.admittime)
          AND t.careunit IN ('SICU', 'MICU', 'CCU', 'CSICU', 'CVICU', 'TSICU', 'NICU')
      ) THEN 'Day-1 ICU' 
      ELSE 'Non-ICU' 
    END AS location_stratum,
    CASE WHEN DATE_DIFF(sc.dischtime, sc.admittime, DAY) <= 5 THEN 1 ELSE 0 END AS is_short_los,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN ckd_codes c ON d.icd_code LIKE CONCAT(c.icd_code, '%')
        WHERE d.subject_id = sc.subject_id AND d.hadm_id = sc.hadm_id AND d.icd_version = '10'
      ) THEN 1 ELSE 0 
    END AS has_ckd,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN diabetes_codes dia ON d.icd_code LIKE CONCAT(dia.icd_code, '%')
        WHERE d.subject_id = sc.subject_id AND d.hadm_id = sc.hadm_id AND d.icd_version = '10'
      ) THEN 1 ELSE 0 
    END AS has_diabetes
  FROM sepsis_cohort sc
)
SELECT 
  los_stratum,
  location_stratum,
  COUNT(*) AS N,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM cohort_with_flags
GROUP BY los_stratum, location_stratum
ORDER BY 
  CASE los_stratum WHEN 'LOS <=5' THEN 1 ELSE 2 END,
  CASE location_stratum WHEN 'Day-1 ICU' THEN 1 ELSE 2 END;