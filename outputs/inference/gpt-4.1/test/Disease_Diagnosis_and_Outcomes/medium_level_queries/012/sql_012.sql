WITH
-- 1. Select women aged 83–93
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 83 AND 93
),

-- 2. Identify admissions with heart failure
hf_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.deathtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN female_patients fp ON adm.subject_id = fp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx ON adm.hadm_id = dx.hadm_id
  WHERE
    ( (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%') )
),

-- 3. Identify ICU admissions
icu_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- 4. Identify CKD and diabetes per admission
ckd_diabetes_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '585%') OR (icd_version = 10 AND icd_code LIKE 'N18%') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '250%') OR (icd_version = 10 AND icd_code BETWEEN 'E10' AND 'E14') THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- 5. Comorbidity burden (excluding heart failure, CKD, diabetes)
comorbidity_burden AS (
  SELECT
    dx.hadm_id,
    COUNT(DISTINCT CASE
      WHEN
        -- Exclude heart failure
        NOT ( (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
               OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%') )
        -- Exclude CKD
        AND NOT ( (dx.icd_version = 9 AND dx.icd_code LIKE '585%')
                  OR (dx.icd_version = 10 AND dx.icd_code LIKE 'N18%') )
        -- Exclude diabetes
        AND NOT ( (dx.icd_version = 9 AND dx.icd_code LIKE '250%')
                  OR (dx.icd_version = 10 AND dx.icd_code BETWEEN 'E10' AND 'E14') )
      THEN CONCAT(dx.icd_version, '-', dx.icd_code)
      ELSE NULL
    END) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  GROUP BY dx.hadm_id
),

-- 6. Combine all features per admission
admission_features AS (
  SELECT
    hf.subject_id,
    hf.hadm_id,
    hf.admittime,
    hf.dischtime,
    hf.deathtime,
    hf.hospital_expire_flag,
    IF(icu.hadm_id IS NOT NULL, 'ICU', 'non-ICU') AS icu_status,
    DATETIME_DIFF(hf.dischtime, hf.admittime, DAY) AS los_days,
    CASE WHEN DATETIME_DIFF(hf.dischtime, hf.admittime, DAY) < 8 THEN '<8' ELSE '≥8' END AS los_group,
    COALESCE(cb.comorbidity_count, 0) AS comorbidity_count,
    CASE
      WHEN COALESCE(cb.comorbidity_count, 0) <= 1 THEN '0–1'
      WHEN COALESCE(cb.comorbidity_count, 0) = 2 THEN '2'
      ELSE '≥3'
    END AS comorbidity_group,
    COALESCE(cd.has_ckd, 0) AS has_ckd,
    COALESCE(cd.has_diabetes, 0) AS has_diabetes
  FROM hf_admissions hf
  LEFT JOIN icu_admissions icu ON hf.hadm_id = icu.hadm_id
  LEFT JOIN comorbidity_burden cb ON hf.hadm_id = cb.hadm_id
  LEFT JOIN ckd_diabetes_flags cd ON hf.hadm_id = cd.hadm_id
)

-- 7. Aggregate and report
SELECT
  icu_status,
  los_group,
  comorbidity_group,
  COUNT(*) AS n_admissions,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS mortality_percent,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(100 * SUM(has_ckd) / COUNT(*), 1) AS ckd_prevalence_percent,
  ROUND(100 * SUM(has_diabetes) / COUNT(*), 1) AS diabetes_prevalence_percent
FROM admission_features
GROUP BY icu_status, los_group, comorbidity_group
ORDER BY icu_status, los_group, comorbidity_group;