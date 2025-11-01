WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Compute birth date from anchor_year and anchor_age
    DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date,
    TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND a.dischtime IS NOT NULL
),
filtered_admissions AS (
  SELECT 
    pa.*,
    d_icd.icd_code,
    d_icd.long_title
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.subject_id = d.subject_id
    AND pa.hadm_id = d.hadm_id
    AND d.seq_num = 1  -- primary diagnosis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code
    AND d.icd_version = d_icd.icd_version
  WHERE 
    pa.age_at_admission BETWEEN 67 AND 77
    AND (LOWER(d_icd.long_title) LIKE '%sepsis%' OR LOWER(d_icd.long_title) LIKE '%septic shock%')
)
SELECT MAX(los_days) AS max_los
FROM filtered_admissions;