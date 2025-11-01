WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.admission_type,
    a.insurance,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    -- Compute age at admission in years without using an intermediate alias
    TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
first_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    admission_type,
    insurance,
    gender,
    age_at_admission,
    -- Assign row number to get the first admission per patient
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM patient_admissions
  WHERE 
    gender = 'F' -- female
    AND age_at_admission BETWEEN 80 AND 90
    AND admission_type = 'EMERGENCY'
    AND insurance LIKE '%Medicare%'
),
principal_diagnoses AS (
  SELECT 
    d.hadm_id,
    d.icd_code,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    d.seq_num = 1 -- principal diagnosis
    AND d.icd_version = 10 -- ICD-10
    AND d.icd_code IN (
      'M86.0', 'M86.1', 'M86.2', 'M86.3', 'M86.4', 'M86.5', 'M86.6', 'M86.7', 'M86.8', 'M86.9'
    )
)
SELECT 
  COUNT(*) AS index_admissions_count
FROM first_admissions f
INNER JOIN principal_diagnoses p
  ON f.hadm_id = p.hadm_id
WHERE f.rn = 1; -- only the first admission;