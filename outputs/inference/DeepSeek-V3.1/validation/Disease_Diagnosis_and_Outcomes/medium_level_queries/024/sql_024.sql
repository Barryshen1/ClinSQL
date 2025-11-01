WITH sepsis_cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Check if ICU stay on day 1 (admittime to admittime + 1 day)
    MAX(CASE 
        WHEN icu.intime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 1 DAY) 
        THEN 1 ELSE 0 
    END) AS icu_day1_flag,
    -- Check for CKD (any diagnosis during admission)
    MAX(CASE 
        WHEN diag_ckd.icd_code IS NOT NULL THEN 1 ELSE 0 
    END) AS ckd_flag,
    -- Check for Diabetes (any diagnosis during admission)
    MAX(CASE 
        WHEN diag_dm.icd_code IS NOT NULL THEN 1 ELSE 0 
    END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  -- Sepsis diagnosis (without septic shock)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_sepsis
    ON a.hadm_id = diag_sepsis.hadm_id
    AND (
      (diag_sepsis.icd_version = 10 AND diag_sepsis.icd_code IN ('A41.9', 'R65.20'))
      OR (diag_sepsis.icd_version = 9 AND diag_sepsis.icd_code = '0389')
    )
  -- Exclude septic shock
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_shock
    ON a.hadm_id = diag_shock.hadm_id
    AND (
      (diag_shock.icd_version = 10 AND diag_shock.icd_code = 'R65.21')
      OR (diag_shock.icd_version = 9 AND diag_shock.icd_code = '78552')
    )
  -- ICU stays for day1 check
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  -- CKD diagnosis
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_ckd
    ON a.hadm_id = diag_ckd.hadm_id
    AND (
      (diag_ckd.icd_version = 10 AND diag_ckd.icd_code LIKE 'N18%')
      OR (diag_ckd.icd_version = 9 AND diag_ckd.icd_code LIKE '585%')
    )
  -- Diabetes diagnosis
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_dm
    ON a.hadm_id = diag_dm.hadm_id
    AND (
      (diag_dm.icd_version = 10 AND diag_dm.icd_code LIKE 'E1%')
      OR (diag_dm.icd_version = 9 AND diag_dm.icd_code LIKE '250%')
    )
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND diag_shock.hadm_id IS NULL  -- Exclude septic shock
  GROUP BY 
    p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
)

SELECT 
  CASE WHEN los_days <= 5 THEN 'LOS ≤5' ELSE 'LOS >5' END AS los_group,
  CASE WHEN icu_day1_flag = 1 THEN 'ICU day1' ELSE 'No ICU day1' END AS icu_group,
  COUNT(*) AS n,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
  ROUND(100 * AVG(ckd_flag), 2) AS ckd_percent,
  ROUND(100 * AVG(diabetes_flag), 2) AS diabetes_percent
FROM sepsis_cohort
GROUP BY 
  los_group, icu_group
ORDER BY 
  los_group, icu_group;