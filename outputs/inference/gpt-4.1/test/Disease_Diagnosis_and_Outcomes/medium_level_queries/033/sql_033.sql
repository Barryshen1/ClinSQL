WITH postop_complications AS (
  -- Find admissions with postoperative complications
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%postoperative complication%'
     OR LOWER(dd.long_title) LIKE '%complication of procedure%'
),
elixhauser_comorbidities AS (
  -- Admissions with Elixhauser comorbidities (see MIMIC code repo for ICD codes)
  SELECT
    d.subject_id,
    d.hadm_id,
    COUNT(DISTINCT ec.comorbidity) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN (
    -- Elixhauser ICD code mapping (simplified, see MIMIC repo for full mapping)
    SELECT comorbidity, icd_code, icd_version FROM UNNEST([
      STRUCT('CONGESTIVE_HEART_FAILURE' AS comorbidity, '4280' AS icd_code, 9 AS icd_version),
      STRUCT('CONGESTIVE_HEART_FAILURE', 'I50', 10),
      STRUCT('DIABETES', '25000', 9),
      STRUCT('DIABETES', 'E10', 10),
      STRUCT('DIABETES', 'E11', 10)
      -- Add more comorbidities as needed for full Elixhauser mapping
    ])
  ) ec
    ON d.icd_code = ec.icd_code AND d.icd_version = ec.icd_version
  GROUP BY d.subject_id, d.hadm_id
),
icu_admissions AS (
  -- Admissions with ICU stay
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
main_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN ia.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS ICU_status,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR), 24) AS los_days,
    COALESCE(ec.comorbidity_count, 0) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN postop_complications pc
    ON a.subject_id = pc.subject_id AND a.hadm_id = pc.hadm_id
  LEFT JOIN elixhauser_comorbidities ec
    ON a.subject_id = ec.subject_id AND a.hadm_id = ec.hadm_id
  LEFT JOIN icu_admissions ia
    ON a.hadm_id = ia.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
)
SELECT
  ICU_status,
  CASE WHEN los_days <= 5 THEN '≤5' ELSE '>5' END AS LOS_bin,
  CASE
    WHEN comorbidity_count <= 1 THEN '0–1'
    WHEN comorbidity_count = 2 THEN '2'
    ELSE '≥3'
  END AS comorbidity_bin,
  COUNT(*) AS N,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS mortality_pct,
  ROUND(AVG(comorbidity_count), 2) AS avg_comorbidity_count
FROM main_cohort
GROUP BY ICU_status, LOS_bin, comorbidity_bin
ORDER BY ICU_status, LOS_bin, comorbidity_bin;