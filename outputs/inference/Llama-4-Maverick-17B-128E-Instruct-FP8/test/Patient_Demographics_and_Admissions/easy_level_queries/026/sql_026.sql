WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 48 AND 58
),
cabg_patients AS (
  SELECT DISTINCT p.subject_id
  FROM eligible_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE d_proc.long_title LIKE '%Coronary artery bypass graft%'
),
first_admissions AS (
  SELECT c.subject_id, 
         a.hadm_id, 
         ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY a.admittime) AS admission_rank,
         a.hospital_expire_flag
  FROM cabg_patients c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.subject_id = a.subject_id
)
SELECT 
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS percentile_25th_mortality
FROM first_admissions
WHERE admission_rank = 1;