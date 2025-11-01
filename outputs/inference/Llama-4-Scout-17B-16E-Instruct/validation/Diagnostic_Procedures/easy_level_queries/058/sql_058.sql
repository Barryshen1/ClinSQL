WITH 
  -- Identify mechanical circulatory support (MCS) procedures
  mcs_procedures AS (
    SELECT 
      icd_code, 
      long_title
    FROM 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE 
      icd_code IN ('00.66', '00.67', '00.68', '00.69', '39.61', '39.62', '39.63', '39.64', 
                   '39.65', '39.66', '39.67', '39.68', '39.69', '86.01', '86.02', '86.03', 
                   '86.04', '86.05', '86.06', '86.07', '86.08', '86.09', '86.10', '86.11', 
                   '86.12', '86.13', '86.14', '86.15', '86.16', '86.17', '86.18', '86.19', 
                   '86.20', '86.21', '86.22', '86.23', '86.24', '86.25', '86.26', '86.27', 
                   '86.28', '86.29', '86.30', '86.31', '86.32', '86.33', '86.34', '86.35', 
                   '86.36', '86.37', '86.38', '86.39', '86.40', '86.41', '86.42', '86.43', 
                   '86.44', '86.45', '86.46', '86.47', '86.48', '86.49', '86.50', '86.51', 
                   '86.52', '86.53', '86.54', '86.55', '86.56', '86.57', '86.58', '86.59', 
                   '86.60', '86.61', '86.62', '86.63', '86.64', '86.65', '86.66', '86.67', 
                   '86.68', '86.69', '86.70', '86.71', '86.72', '86.73', '86.74', '86.75', 
                   '86.76', '86.77', '86.78', '86.79', '86.80', '86.81', '86.82', '86.83', 
                   '86.84', '86.85', '86.86', '86.87', '86.88', '86.89', '86.90', '86.91', 
                   '86.92', '86.93', '86.94', '86.95', '86.96', '86.97', '86.98', '86.99')
  ),
  
  -- Filter patients and join with admissions and procedures
  patient_procedures AS (
    SELECT 
      a.hadm_id,
      p.subject_id,
      pi.icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON 
      a.hadm_id = pi.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 86 AND 96
      AND pi.icd_code IN (SELECT icd_code FROM mcs_procedures)
  ),
  
  -- Count distinct MCS procedures per hospitalization
  mcs_counts AS (
    SELECT 
      hadm_id,
      COUNT(DISTINCT icd_code) AS mcs_count
    FROM 
      patient_procedures
    GROUP BY 
      hadm_id
  )

-- Calculate IQR of distinct MCS procedures per hospitalization
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY mcs_count) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY mcs_count) AS iqr
FROM 
  mcs_counts;