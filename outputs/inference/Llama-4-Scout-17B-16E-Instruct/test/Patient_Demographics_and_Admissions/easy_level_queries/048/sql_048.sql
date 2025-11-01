WITH 
  -- Identify heart failure ICD codes
  heart_failure_icd AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Heart failure%'
  ),

  -- Identify patients with heart failure in first admission
  patients_with_hf AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      EXTRACT(DAY FROM a.dischtime - a.admittime) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 79 AND 89
      AND d.icd_code IN (SELECT icd_code FROM heart_failure_icd)
  ),

  -- Filter first admissions
  first_admissions AS (
    SELECT 
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      los_days,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM 
      patients_with_hf
  )

-- Calculate IQR of LOS for first admissions
SELECT 
  APPROX_QUANTILES(los_days, 0.25)[OFFSET(0)] AS q1,
  APPROX_QUANTILES(los_days, 0.75)[OFFSET(0)] AS q3,
  APPROX_QUANTILES(los_days, 0.75)[OFFSET(0)] - 
  APPROX_QUANTILES(los_days, 0.25)[OFFSET(0)] AS iqr
FROM 
  first_admissions
WHERE 
  rn = 1;