WITH copd_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN INT64(49) AND INT64(59)
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'J44%'
    AND a.hospital_expire_flag = 0
    AND a.admission_type != 'OBSERVATION'  -- Focus on inpatient admissions
)
SELECT 
  PERCENTILE_CONT(0.25) OVER() AS p25_los_days
FROM 
  copd_cohort
WHERE 
  los_days > 0  -- Exclude any zero/negative LOS edge cases;