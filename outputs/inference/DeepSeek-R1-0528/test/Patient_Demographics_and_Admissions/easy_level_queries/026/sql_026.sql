WITH cabg_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%coronary artery bypass%' 
    OR LOWER(long_title) LIKE '%cabg%'
),
first_admission AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN (
    SELECT subject_id, MIN(admittime) AS first_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
  ) AS fa 
  ON a.subject_id = fa.subject_id AND a.admittime = fa.first_admittime
),
cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    fa.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN first_admission fa 
    ON p.subject_id = fa.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
    ON fa.hadm_id = proc.hadm_id
  INNER JOIN cabg_codes cc 
    ON proc.icd_code = cc.icd_code 
    AND proc.icd_version = cc.icd_version
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 48 AND 58
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100, 2) AS mortality_rate_percent
FROM cohort;