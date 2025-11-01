WITH hf_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di_cd
    ON a.hadm_id = di_cd.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di
    ON di_cd.icd_code = di.icd_code AND di_cd.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND (di.long_title LIKE '%heart failure%' 
         OR di.icd_code LIKE '428%' 
         OR di.icd_code LIKE 'I50%')
),

comorbidities AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    MAX(CASE 
      WHEN di.long_title LIKE '%diabetes%' 
        OR di.icd_code LIKE '250%' 
        OR di.icd_code LIKE 'E10%' 
        OR di.icd_code LIKE 'E11%' 
        OR di.icd_code LIKE 'E13%' 
        OR di.icd_code LIKE 'E14%' 
      THEN 1 
      ELSE 0 
    END) AS has_diabetes,
    MAX(CASE 
      WHEN di.long_title LIKE '%chronic kidney disease%' 
        OR di.long_title LIKE '%kidney failure, chronic%' 
        OR di.icd_code LIKE '585%' 
        OR di.icd_code LIKE 'N18%' 
      THEN 1 
      ELSE 0 
    END) AS has_ckd
  FROM hf_patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di_cd
    ON p.subject_id = di_cd.subject_id AND p.hadm_id = di_cd.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di
    ON di_cd.icd_code = di.icd_code AND di_cd.icd_version = di.icd_version
  GROUP BY p.subject_id, p.hadm_id
),

final_data AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.los_days,
    p.hospital_expire_flag,
    c.has_diabetes,
    c.has_ckd,
    CASE 
      WHEN p.los_days <= 5 THEN '≤5 days'
      ELSE '>5 days'
    END AS los_group,
    CASE 
      WHEN (c.has_diabetes + c.has_ckd) = 0 THEN 'Low'
      WHEN (c.has_diabetes + c.has_ckd) = 1 THEN 'Med'
      WHEN (c.has_diabetes + c.has_ckd) = 2 THEN 'High'
    END AS comorbidity_tertile
  FROM hf_patients p
  INNER JOIN comorbidities c
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
)

SELECT
  los_group,
  comorbidity_tertile,
  COUNT(*) AS N,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
  ROUND(100.0 * SUM(has_diabetes) / COUNT(*), 2) AS diabetes_prevalence_pct,
  ROUND(100.0 * SUM(has_ckd) / COUNT(*), 2) AS ckds_prevalence_pct
FROM final_data
GROUP BY los_group, comorbidity_tertile
ORDER BY los_group, comorbidity_tertile;