WITH qualifying_admissions AS (
  SELECT DISTINCT 
    a.hadm_id,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 1
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hospital_expire_flag = 0
    AND (
      -- Pneumonia: ICD-9 480-486, ICD-10 J12-J18, J09-J11
      (d.icd_version = '9' AND REGEXP_CONTAINS(d.icd_code, r'^48[0-6]'))
      OR (d.icd_version = '10' AND REGEXP_CONTAINS(d.icd_code, r'^J(09|1[2-8])'))
      OR -- COPD: ICD-9 491-492, ICD-10 J44
      (d.icd_version = '9' AND REGEXP_CONTAINS(d.icd_code, r'^49[1-2]'))
      OR (d.icd_version = '10' AND d.icd_code LIKE 'J44%')
    )
)

SELECT 
  PERCENTILE_CONT(0.75) AS p75_los_days
FROM 
  qualifying_admissions
WHERE 
  los_days IS NOT NULL;