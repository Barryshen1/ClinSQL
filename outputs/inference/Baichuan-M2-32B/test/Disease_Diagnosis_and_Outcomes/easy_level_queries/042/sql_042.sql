WITH 
  -- Define ICD codes for ischemic heart disease and ACS (both ICD-9 and ICD-10)
  icd_codes AS (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE 
      (icd_version = 9 AND icd_code BETWEEN '410' AND '414') 
      OR (icd_version = 10 AND icd_code BETWEEN 'I20' AND 'I25')
  ),
  -- Compute patient age at admission using anchor_year and anchor_age to estimate birth date
  patient_age AS (
    SELECT 
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      -- Estimate birth date: subtract anchor_age from the first day of anchor_year
      DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR) AS birth_date,
      -- Age at admission in years
      DATE_DIFF(a.admittime, DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  ),
  -- Filter for female patients aged exactly 83 at admission
  filtered_patients AS (
    SELECT 
      pa.subject_id,
      pa.hadm_id,
      pa.admittime,
      pa.dischtime,
      pa.age_at_admission
    FROM patient_age pa
    WHERE 
      pa.age_at_admission = 83
      AND (SELECT gender FROM `physionet-data.mimiciv_3_1_hosp.patients` p WHERE p.subject_id = pa.subject_id) = 'F'
  ),
  -- Get primary diagnoses (seq_num=1) for these admissions
  primary_diagnoses AS (
    SELECT 
      d.subject_id,
      d.hadm_id,
      d.icd_code,
      d.icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN filtered_patients fp ON d.subject_id = fp.subject_id AND d.hadm_id = fp.hadm_id
    WHERE d.seq_num = 1
  ),
  -- Join with icd_codes to filter for relevant diagnoses
  relevant_diagnoses AS (
    SELECT 
      pd.subject_id,
      pd.hadm_id
    FROM primary_diagnoses pd
    INNER JOIN icd_codes ic ON pd.icd_code = ic.icd_code AND pd.icd_version = ic.icd_version
  ),
  -- Compute LOS for these admissions
  los_data AS (
    SELECT 
      fp.hadm_id,
      TIMESTAMP_DIFF(fp.dischtime, fp.admittime, DAY) AS los_days
    FROM filtered_patients fp
    INNER JOIN relevant_diagnoses rd ON fp.hadm_id = rd.hadm_id
  )
-- Average LOS
SELECT AVG(los_days) AS avg_los
FROM los_data;