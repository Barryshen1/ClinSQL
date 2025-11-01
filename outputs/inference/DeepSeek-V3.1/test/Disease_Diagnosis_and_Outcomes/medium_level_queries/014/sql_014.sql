WITH hf_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) >= 8 THEN '>=8'
    END AS los_category,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
        WHERE icu.hadm_id = adm.hadm_id
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status,
    -- Check for CKD
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE diag.hadm_id = adm.hadm_id 
        AND diag.icd_code LIKE 'N18%' 
        AND diag.icd_version = 10
    ) AS has_ckd,
    -- Check for Diabetes
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE diag.hadm_id = adm.hadm_id 
        AND (diag.icd_code LIKE 'E10%' OR diag.icd_code LIKE 'E11%' OR diag.icd_code LIKE 'E13%')
        AND diag.icd_version = 10
    ) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_hf
      WHERE diag_hf.hadm_id = adm.hadm_id
        AND diag_hf.icd_code LIKE 'I50%'
        AND diag_hf.icd_version = 10
    )
)

SELECT 
  icu_status,
  los_category,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percent,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 1) AS median_los,
  ROUND(100.0 * SUM(CAST(has_ckd AS INT)) / COUNT(*), 1) AS ckd_percent,
  ROUND(100.0 * SUM(CAST(has_diabetes AS INT)) / COUNT(*), 1) AS diabetes_percent
FROM hf_admissions
WHERE los_days >= 1
GROUP BY icu_status, los_category
ORDER BY icu_status, los_category;