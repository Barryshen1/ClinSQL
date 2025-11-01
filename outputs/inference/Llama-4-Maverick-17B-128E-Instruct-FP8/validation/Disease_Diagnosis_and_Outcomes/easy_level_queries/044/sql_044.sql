WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 61 AND 71
),
heart_failure_admissions AS (
  SELECT 
    d.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    d.seq_num = 1
    AND LOWER(icd.long_title) LIKE '%heart failure%'
)
SELECT 
  AVG(pa.los) AS avg_los
FROM 
  patient_admissions pa
INNER JOIN 
  heart_failure_admissions hfa ON pa.hadm_id = hfa.hadm_id;