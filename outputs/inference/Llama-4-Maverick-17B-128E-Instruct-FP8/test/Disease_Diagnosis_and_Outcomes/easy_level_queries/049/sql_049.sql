WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 50 AND 60
),
stroke_admissions AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.los,
    ROW_NUMBER() OVER (PARTITION BY pa.hadm_id ORDER BY d.seq_num) AS diagnosis_rank
  FROM 
    patient_admissions pa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON pa.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    dicd.long_title LIKE '%Ischemic stroke%'
)
SELECT 
  PERCENTILE_CONT(los, 0.25) OVER () AS percentile_25th_los
FROM 
  stroke_admissions
WHERE 
  diagnosis_rank = 1
LIMIT 1;