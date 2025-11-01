WITH hip_fracture_admissions AS (
  SELECT 
    di.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN (
    SELECT 
      hadm_id, 
      MIN(seq_num) AS min_seq_num
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      hadm_id
  ) principal_dx 
    ON di.hadm_id = principal_dx.hadm_id 
    AND di.seq_num = principal_dx.min_seq_num
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code 
    AND di.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%hip%fracture%'
)

SELECT 
  COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON a.subject_id = p.subject_id
INNER JOIN 
  hip_fracture_admissions hf 
  ON a.hadm_id = hf.hadm_id
WHERE 
  a.admission_location = 'Transfer from another hospital'
  AND a.insurance = 'Medicare'
  AND p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 46 AND 56;