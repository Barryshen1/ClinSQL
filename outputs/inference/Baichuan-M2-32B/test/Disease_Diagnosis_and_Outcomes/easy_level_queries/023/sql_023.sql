WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    (p.anchor_year - p.anchor_age) AS birth_year,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND a.admission_type IN ('Elective', 'Emergency', 'Urgent')
),
primary_diagnoses AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    ROW_NUMBER() OVER (PARTITION BY d.subject_id, d.hadm_id ORDER BY d.seq_num) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN patient_admissions pa 
    ON d.subject_id = pa.subject_id AND d.hadm_id = pa.hadm_id
),
pneumonia_diagnoses AS (
  SELECT 
    pd.subject_id,
    pd.hadm_id,
    pd.icd_code,
    pd.icd_version,
    di.long_title
  FROM primary_diagnoses pd
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON pd.icd_code = di.icd_code AND pd.icd_version = di.icd_version
  WHERE pd.rn = 1
    AND LOWER(di.long_title) LIKE '%pneumonia%'
),
eligible_admissions AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days
  FROM patient_admissions pa
  INNER JOIN pneumonia_diagnoses pd 
    ON pa.subject_id = pd.subject_id AND pa.hadm_id = pd.hadm_id
  WHERE pa.age_at_admission BETWEEN 83 AND 93
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
FROM eligible_admissions;