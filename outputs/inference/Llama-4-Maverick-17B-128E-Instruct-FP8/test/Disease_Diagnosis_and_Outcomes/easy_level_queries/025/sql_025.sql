WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admittime IS NOT NULL 
    AND a.dischtime IS NOT NULL
),
primary_diagnosis AS (
  SELECT 
    hadm_id,
    icd_code,
    icd_version,
    seq_num
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),
upper_gi_bleeding_admissions AS (
  SELECT 
    pa.hadm_id,
    pa.los_days
  FROM 
    patient_admissions pa
  INNER JOIN 
    primary_diagnosis pd ON pa.hadm_id = pd.hadm_id
  WHERE 
    pd.seq_num = 1 
    AND (pd.icd_code LIKE 'K92.0%' OR pd.icd_code LIKE 'K92.1%' OR pd.icd_code LIKE 'K92.2%')
),
los_data AS (
  SELECT 
    los_days
  FROM 
    upper_gi_bleeding_admissions
)

SELECT 
  STDDEV(los_days) AS sd_los_days
FROM 
  los_data;