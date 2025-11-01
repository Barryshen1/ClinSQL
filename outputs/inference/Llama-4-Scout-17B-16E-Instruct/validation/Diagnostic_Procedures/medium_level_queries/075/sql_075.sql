WITH 
  -- Filter patients and admissions of interest
  patients_of_interest AS (
    SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, a.admission_type
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 59 AND 69
  ),
  
  -- Identify ACS admissions and primary/secondary diagnosis
  acs_admissions AS (
    SELECT pai.hadm_id, 
           di.seq_num,
           CASE 
             WHEN di.icd_code IN ('410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9') THEN 'ACS'
             ELSE 'Non-ACS'
           END AS acs_status,
           CASE 
             WHEN di.seq_num = 1 THEN 'Primary'
             ELSE 'Secondary'
           END AS diagnosis_type
    FROM patients_of_interest pai
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON pai.hadm_id = di.hadm_id
  ),
  
  -- Filter ACS admissions
  acs_admissions_filtered AS (
    SELECT hadm_id, seq_num, acs_status, diagnosis_type
    FROM acs_admissions
    WHERE acs_status = 'ACS'
  ),
  
  -- Calculate length of stay and categorize
  admissions_categorized AS (
    SELECT acf.hadm_id,
           acf.acs_status,
           acf.diagnosis_type,
           CASE 
             WHEN TIMESTAMP_DIFF(pai.dischtime, pai.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
             WHEN TIMESTAMP_DIFF(pai.dischtime, pai.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
             ELSE 'Outside range'
           END AS los_category
    FROM acs_admissions_filtered acf
    JOIN patients_of_interest pai ON acf.hadm_id = pai.hadm_id
  ),
  
  -- Count diagnostic procedures per admission
  procedures_per_admission AS (
    SELECT ac.hadm_id, ac.acs_status, ac.diagnosis_type, ac.los_category, COUNT(DISTINCT p.icd_code) AS num_procedures
    FROM admissions_categorized ac
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON ac.hadm_id = p.hadm_id
    GROUP BY ac.hadm_id, ac.acs_status, ac.diagnosis_type, ac.los_category
  )

-- Calculate percentiles
SELECT 
  los_category,
  diagnosis_type,
  APPROX_QUANTILES(num_procedures, 0.25)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_procedures, 0.5)[OFFSET(1)] AS p50,
  APPROX_QUANTILES(num_procedures, 0.75)[OFFSET(1)] AS p75
FROM procedures_per_admission
GROUP BY los_category, diagnosis_type;