WITH hf_patients AS (
  -- Identify first HF admissions for women 38-48
  SELECT DISTINCT
    p.subject_id,
    adm.hadm_id AS index_hadm_id,
    adm.admittime AS index_admittime,
    adm.dischtime AS index_dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id 
    AND adm.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND diag.seq_num = 1  -- Primary diagnosis
    AND (
      (diag.icd_version = 'ICD-10' AND diag.icd_code LIKE 'I50%') OR
      (diag.icd_version = 'ICD-9' AND diag.icd_code LIKE '428%')
    )
    AND adm.dischtime IS NOT NULL  -- Exclude in-hospital deaths or open admissions
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY adm.admittime ASC) = 1  -- First HF admission
),

readmissions AS (
  -- Find any readmissions within 30 days for these index admissions
  SELECT 
    hf.subject_id,
    hf.index_hadm_id,
    hf.index_dischtime,
    adm2.hadm_id AS readmit_hadm_id,
    adm2.admittime AS readmit_admittime,
    DATE(adm2.admittime) - DATE(hf.index_dischtime) AS days_to_readmit
  FROM 
    hf_patients hf
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm2
    ON hf.subject_id = adm2.subject_id
  WHERE 
    adm2.hadm_id != hf.index_hadm_id  -- Exclude index admission
    AND adm2.admittime > hf.index_dischtime  -- Subsequent admissions only
    AND DATE(adm2.admittime) - DATE(hf.index_dischtime) <= 30
)

SELECT 
  COUNT(DISTINCT r.subject_id) AS num_with_readmission,
  COUNT(DISTINCT hf.subject_id) AS total_patients,
  ROUND(AVG(CASE WHEN r.subject_id IS NOT NULL THEN 1.0 ELSE 0.0 END) * 100, 2) AS avg_30day_readmission_rate_percent
FROM 
  hf_patients hf
LEFT JOIN 
  readmissions r
  ON hf.subject_id = r.subject_id;