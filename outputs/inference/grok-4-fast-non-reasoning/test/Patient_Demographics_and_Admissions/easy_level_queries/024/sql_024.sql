WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
),
cabg_cohort AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    fa.gender,
    fa.anchor_age,
    fa.hospital_expire_flag
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` d
    ON fa.subject_id = d.subject_id 
    AND fa.hadm_id = d.hadm_id
    AND d.icd_version = 10
    AND d.icd_code LIKE 'Z95.5%'
  WHERE fa.rn = 1
)
SELECT 
  gender,
  COUNT(*) AS num_patients,
  SUM(hospital_expire_flag) AS num_deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_percent
FROM cabg_cohort
GROUP BY gender
ORDER BY gender;