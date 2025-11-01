WITH stroke_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS hospital_los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND EXTRACT(YEAR FROM a.admittime) >= 2008
    AND d.icd_version = '10'
    AND d.icd_code = 'I61'
    AND d.seq_num = 1
)
SELECT 
  STDDEV(hospital_los) AS sd_hospital_los
FROM 
  stroke_cohort
HAVING 
  COUNT(*) > 1;