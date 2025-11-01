WITH
-- Base patient cohort: women 83-93 with heart failure
patient_cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu,
    -- Comorbidity count (excluding heart failure)
    COUNT(DISTINCT CASE WHEN d.icd_code NOT LIKE 'I50.%' AND d.icd_code NOT LIKE '428.%' THEN d.icd_code END) AS comorbidity_count,
    -- CKD flag
    MAX(CASE WHEN d.icd_code LIKE 'N18.%' THEN 1 ELSE 0 END) AS has_ckd,
    -- Diabetes flag
    MAX(CASE WHEN d.icd_code LIKE 'E11.%' OR d.icd_code LIKE '250.%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND (d.icd_code LIKE 'I50.%' OR d.icd_code LIKE '428.%') -- Heart failure codes
  GROUP BY
    p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, los_days, is_icu
),

-- Stratified results
stratified_results AS (
  SELECT
    is_icu,
    CASE WHEN los_days < 8 THEN 'LOS <8' ELSE 'LOS ≥8' END AS los_stratum,
    CASE
      WHEN comorbidity_count BETWEEN 0 AND 1 THEN '0-1'
      WHEN comorbidity_count = 2 THEN '2'
      ELSE '≥3'
    END AS comorbidity_stratum,
    COUNT(*) AS patient_count,
    SUM(hospital_expire_flag) AS death_count,
    ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
    ROUND(AVG(los_days), 1) AS median_los,
    SUM(has_ckd) AS ckd_count,
    ROUND(100 * SUM(has_ckd) / COUNT(*), 1) AS ckd_prevalence,
    SUM(has_diabetes) AS diabetes_count,
    ROUND(100 * SUM(has_diabetes) / COUNT(*), 1) AS diabetes_prevalence
  FROM
    patient_cohort
  GROUP BY
    is_icu, los_stratum, comorbidity_stratum
)

-- Final output
SELECT
  CASE WHEN is_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
  los_stratum,
  comorbidity_stratum,
  patient_count,
  mortality_pct,
  median_los,
  ckd_prevalence,
  diabetes_prevalence
FROM
  stratified_results
ORDER BY
  is_icu, los_stratum, comorbidity_stratum;