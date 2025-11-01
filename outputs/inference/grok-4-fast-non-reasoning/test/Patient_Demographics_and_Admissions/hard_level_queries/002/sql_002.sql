WITH index_admissions AS (
  SELECT 
    a.hadm_id,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location LIKE '%EMERGENCY%'
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code = 'J18.9'
)
SELECT 
  COUNT(DISTINCT hadm_id) AS total_index_admissions
FROM 
  index_admissions
WHERE 
  rn = 1;