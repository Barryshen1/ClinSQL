WITH stroke_admissions AS (
  SELECT DISTINCT 
    di.subject_id,
    di.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code 
    AND di.icd_version = d.icd_version
  WHERE 
    di.seq_num = 1
    AND di.icd_version = 10
    AND d.icd_code LIKE 'I6%'
)
SELECT 
  PERCENTILE_CONT(0.5, los) AS median_los_days
FROM 
  `physionet-data.mimiciv_3_1_icu.icustays` i
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON i.subject_id = p.subject_id
INNER JOIN 
  stroke_admissions sa 
  ON i.subject_id = sa.subject_id 
  AND i.hadm_id = sa.hadm_id
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 35 AND 45;