WITH heart_failure_cohorts AS (
  -- Base cohort: females 80-90 with heart failure admission
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- ICU flag: any transfer to ICU careunit
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.transfers` t 
      WHERE t.hadm_id = a.hadm_id 
        AND LOWER(t.careunit) LIKE '%icu%'
    ) THEN 1 ELSE 0 END AS icu_flag,
    -- CKD flag
    MAX(CASE WHEN di.icd_code LIKE 'N18%' OR di.icd_code LIKE '585%' OR di.icd_code = '586' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) AS has_ckd,
    -- Diabetes flag
    MAX(CASE WHEN di.icd_code LIKE 'E1[0-3]%' OR di.icd_code LIKE '250%' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
    ON di.icd_code = d_icd.icd_code 
    AND di.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (a.dischtime IS NOT NULL)
    AND (
      -- Heart failure: ICD-10 I50 or ICD-9 428
      (di.icd_version = '10' AND di.icd_code LIKE 'I50%') OR
      (di.icd_version = '9' AND di.icd_code LIKE '428%')
    )
)

-- Aggregate by strata
SELECT 
  CASE WHEN icu_flag = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_stratum,
  CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_stratum,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM heart_failure_cohorts
GROUP BY icu_flag, 
  CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END
ORDER BY icu_stratum, los_stratum;