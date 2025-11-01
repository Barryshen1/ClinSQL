WITH cohort AS (
  SELECT DISTINCT 
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.insurance,
    a.admission_location,
    d.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER'
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'S72%'
)
SELECT 
  COUNT(*) AS num_index_admissions
FROM cohort;