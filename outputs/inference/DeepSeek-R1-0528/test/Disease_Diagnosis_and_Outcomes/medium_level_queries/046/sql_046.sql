WITH hf_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    patients.anchor_age,
    patients.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
    ON adm.subject_id = patients.subject_id
  WHERE patients.gender = 'M'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
      WHERE diag.subject_id = adm.subject_id 
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),

comorbidity_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

icu_flags AS (
  SELECT 
    hadm_id,
    1 AS has_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital,
    adm.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - adm.anchor_year) AS age_at_admission,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS ICU_status
  FROM hf_admissions AS adm
  LEFT JOIN comorbidity_counts AS cc
    ON adm.hadm_id = cc.hadm_id
  LEFT JOIN icu_flags AS icu
    ON adm.hadm_id = icu.hadm_id
)

SELECT 
  ICU_status,
  CASE 
    WHEN los_hospital <= 3 THEN '<=3'
    WHEN los_hospital BETWEEN 4 AND 6 THEN '4-6'
    WHEN los_hospital BETWEEN 7 AND 10 THEN '7-10'
    ELSE '>10'
  END AS los_group,
  COUNT(*) AS num_admissions,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate,
  AVG(comorbidity_count) AS avg_comorbidity_count,
  APPROX_QUANTILES(los_hospital, 100 RESPECT NULLS)[OFFSET(50)] AS median_los
FROM cohort
WHERE age_at_admission BETWEEN 72 AND 82
GROUP BY ICU_status, los_group
ORDER BY ICU_status, 
  CASE los_group
    WHEN '<=3' THEN 1
    WHEN '4-6' THEN 2
    WHEN '7-10' THEN 3
    ELSE 4
  END;