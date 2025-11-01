WITH hf_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    CASE 
      WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 
    END AS icu_flag,
    DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  -- heart failure ICD-9 428.xx or ICD-10 I50.xxx
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
    )
  GROUP BY adm.subject_id, adm.hadm_id, pat.gender, pat.anchor_age,
           adm.admittime, adm.dischtime, adm.hospital_expire_flag, icu_flag
),
comorbidities AS (
  SELECT
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '585%') 
            OR (icd_version = 10 AND icd_code LIKE 'N18%') 
          THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '250%') 
            OR (icd_version = 10 AND (
                  icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' 
                  OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'
                ))
          THEN 1 ELSE 0 END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT
  CASE WHEN icu_flag = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
  CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
  COUNT(*) AS n_admissions,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS mortality_pct,
  ROUND(100 * SUM(CASE WHEN ckd_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS ckd_pct,
  ROUND(100 * SUM(CASE WHEN diabetes_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS diabetes_pct
FROM hf_cohort h
LEFT JOIN comorbidities c
  ON h.hadm_id = c.hadm_id
GROUP BY icu_status, los_group
ORDER BY icu_status, los_group;