WITH first_admission_with_pneumonia AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_rank
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
)
SELECT 
  ROUND(
    100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 
    2
  ) AS in_hospital_mortality_percent
FROM 
  first_admission_with_pneumonia
WHERE 
  admission_rank = 1;