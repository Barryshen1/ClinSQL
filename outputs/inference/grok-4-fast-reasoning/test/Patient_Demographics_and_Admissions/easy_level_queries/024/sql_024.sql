WITH first_admissions AS (
  SELECT 
    subject_id, 
    MIN(admittime) AS min_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY subject_id
),
cabg_cohort AS (
  SELECT DISTINCT 
    a.hadm_id, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN first_admissions fa
    ON a.subject_id = fa.subject_id 
    AND a.admittime = fa.min_admittime
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.subject_id = proc.subject_id 
    AND a.hadm_id = proc.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
    AND (
      (proc.icd_version = 9 AND proc.icd_code LIKE '36.1%')
      OR 
      (proc.icd_version = 10 AND proc.icd_code LIKE '021%')
    )
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent
FROM cabg_cohort;