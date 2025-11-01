WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 49 AND 59
),
pneumonia_admissions AS (
  SELECT DISTINCT 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE 
    LOWER(dicd.long_title) LIKE '%pneumonia%'
),
filtered_admissions AS (
  SELECT 
    pa.los_days
  FROM 
    patient_admissions pa
  INNER JOIN 
    pneumonia_admissions pna ON pa.hadm_id = pna.hadm_id
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25_los
FROM 
  filtered_admissions;