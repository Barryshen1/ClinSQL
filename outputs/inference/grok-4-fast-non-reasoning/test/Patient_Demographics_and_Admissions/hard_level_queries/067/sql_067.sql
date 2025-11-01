WITH cohort AS (
  SELECT DISTINCT 
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_age BETWEEN 43 AND 53
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'K56%'
)
SELECT 
  COUNT(hadm_id) AS num_completed_index_admissions
FROM 
  cohort;