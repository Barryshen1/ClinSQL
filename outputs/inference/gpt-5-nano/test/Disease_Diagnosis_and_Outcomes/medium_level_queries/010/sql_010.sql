WITH base AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS_days,
    -- comorbidity flags
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_ckd
      WHERE di_ckd.hadm_id = a.hadm_id
        AND di_ckd.icd_code LIKE '585%'
    ) THEN 1 ELSE 0 END AS ckd_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_dm
      WHERE di_dm.hadm_id = a.hadm_id
        AND di_dm.icd_code LIKE '250%'
    ) THEN 1 ELSE 0 END AS diabetes_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_chf
      WHERE di_chf.hadm_id = a.hadm_id
        AND di_chf.icd_code LIKE '428%'
    ) THEN 1 ELSE 0 END AS chf_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_copd
      WHERE di_copd.hadm_id = a.hadm_id
        AND (di_copd.icd_code LIKE '491%' OR di_copd.icd_code LIKE '492%' OR di_copd.icd_code LIKE '496%')
    ) THEN 1 ELSE 0 END AS copd_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_liv
      WHERE di_liv.hadm_id = a.hadm_id
        AND (di_liv.icd_code LIKE '570%' OR di_liv.icd_code LIKE '571%' OR di_liv.icd_code LIKE '572%')
    ) THEN 1 ELSE 0 END AS liver_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    -- AMI: ICD-9-CM 410.x
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diAMI
      WHERE diAMI.hadm_id = a.hadm_id
        AND diAMI.icd_code LIKE '410%'
    )
    -- Exclude shock/respiratory failure
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diSh
      WHERE diSh.hadm_id = a.hadm_id
        AND (diSh.icd_code LIKE '518.8%' OR diSh.icd_code LIKE '785.5%')
    )
    -- Ensure the admission has discharge time (to compute LOS)
    AND a.dischtime IS NOT NULL
),
-- Derive LOS quartile and mortality, and compute burden label
expanded AS (
  SELECT
    hadm_id,
    LOS_days,
    ckd_flag,
    diabetes_flag,
    chf_flag,
    copd_flag,
    liver_flag,
    hospital_expire_flag,
    -- Mortality indicator for in-hospital death
    CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END AS hospital_mort,
    -- LOS quartile (1-4) based on LOS_days
    NTILE(4) OVER (ORDER BY LOS_days) AS los_quartile,
    -- Comorbidity burden
    (ckd_flag + diabetes_flag + chf_flag + copd_flag + liver_flag) AS comorb_count,
    -- Burden category
    CASE
      WHEN (ckd_flag + diabetes_flag + chf_flag + copd_flag + liver_flag) <= 1 THEN 'low'
      WHEN (ckd_flag + diabetes_flag + chf_flag + copd_flag + liver_flag) <= 3 THEN 'medium'
      ELSE 'high'
    END AS burden_label
  FROM base
)
SELECT
  los_quartile,
  burden_label,
  COUNT(*) AS n,
  SUM(hospital_mort) AS deaths,
  100.0 * SUM(hospital_mort) / COUNT(*) AS mortality_rate_percent,
  100.0 * SUM(ckd_flag) / COUNT(*) AS ckd_prevalence_percent,
  100.0 * SUM(diabetes_flag) / COUNT(*) AS diabetes_prevalence_percent
FROM expanded
GROUP BY los_quartile, burden_label
ORDER BY los_quartile, burden_label;