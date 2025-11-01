WITH
-- Define ICH ICD codes
ich_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I60.%'
     OR icd_code LIKE 'I61.%'
     OR icd_code LIKE 'I62.%'
),

-- Get female patients aged 69-79 with ICH
ich_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE WHEN a.deathtime IS NOT NULL OR p.dod IS NOT NULL THEN 1 ELSE 0 END AS died_in_hospital,
    CASE WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
         WHEN p.dod IS NOT NULL AND TIMESTAMP_DIFF(p.dod, a.admittime, DAY) <= 30 THEN 1
         ELSE 0 END AS died_within_30_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN ich_codes ic ON d.icd_code = ic.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
),

-- Calculate Charlson Comorbidity Index (simplified version)
cci_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
          WHEN icd_code IN ('I10', 'I11.0', 'I11.9', 'I12.0', 'I12.9', 'I13.0', 'I13.1', 'I13.10', 'I13.11', 'I13.2', 'I13.9', 'I15.0', 'I15.1', 'I15.2', 'I15.8', 'I15.9') THEN 1
          WHEN icd_code IN ('E10.00', 'E10.01', 'E10.10', 'E10.11', 'E10.21', 'E10.22', 'E10.29', 'E10.311', 'E10.319', 'E10.321', 'E10.329', 'E10.331', 'E10.339', 'E10.341', 'E10.349', 'E10.351', 'E10.359', 'E10.36', 'E10.37X11', 'E10.37X19', 'E10.37X21', 'E10.37X29', 'E10.39', 'E10.40', 'E10.41', 'E10.42', 'E10.43', 'E10.44', 'E10.49', 'E10.51', 'E10.59', 'E10.610', 'E10.618', 'E10.620', 'E10.621', 'E10.622', 'E10.628', 'E10.630', 'E10.638', 'E10.641', 'E10.649', 'E10.65', 'E10.69', 'E10.8', 'E10.9') THEN 1
          WHEN icd_code IN ('I21.01', 'I21.02', 'I21.09', 'I21.11', 'I21.19', 'I21.2', 'I21.3', 'I21.4', 'I21.9', 'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9', 'I25.10', 'I25.110', 'I25.111', 'I25.118', 'I25.119', 'I25.19', 'I25.2', 'I25.3', 'I25.41', 'I25.42', 'I25.5', 'I25.6', 'I25.700', 'I25.701', 'I25.708', 'I25.709', 'I25.710', 'I25.711', 'I25.718', 'I25.719', 'I25.720', 'I25.721', 'I25.728', 'I25.729', 'I25.730', 'I25.731', 'I25.738', 'I25.739', 'I25.740', 'I25.741', 'I25.748', 'I25.749', 'I25.750', 'I25.751', 'I25.758', 'I25.759', 'I25.760', 'I25.761', 'I25.768', 'I25.769', 'I25.79', 'I25.810', 'I25.811', 'I25.812', 'I25.818', 'I25.819', 'I25.82', 'I25.83', 'I25.84', 'I25.89', 'I25.9') THEN 1
          WHEN icd_code IN ('C00.0', 'C00.1', 'C00.2', 'C00.3', 'C00.4', 'C00.5', 'C00.6', 'C00.8', 'C00.9', 'C01', 'C02.0', 'C02.1', 'C02.2', 'C02.3', 'C02.4', 'C02.8', 'C02.9', 'C03.0', 'C03.1', 'C03.9', 'C04.0', 'C04.1', 'C04.8', 'C04.9', 'C05.0', 'C05.1', 'C05.2', 'C05.8', 'C05.9', 'C06.0', 'C06.1', 'C06.2', 'C06.8', 'C06.9', 'C07', 'C08.0', 'C08.1', 'C08.8', 'C08.9', 'C09.0', 'C09.1', 'C09.8', 'C09.9', 'C10.0', 'C10.1', 'C10.2', 'C10.3', 'C10.8', 'C10.9', 'C11.0', 'C11.1', 'C11.2', 'C11.3', 'C11.8', 'C11.9', 'C12', 'C13.0', 'C13.1', 'C13.2', 'C13.8', 'C13.9', 'C14.0', 'C14.2', 'C14.8', 'C14.9', 'C15.3', 'C15.4', 'C15.5', 'C15.8', 'C15.9', 'C16.0', 'C16.1', 'C16.2', 'C16.3', 'C16.4', 'C16.5', 'C16.6', 'C16.8', 'C16.9', 'C17.0', 'C17.1', 'C17.2', 'C17.3', 'C17.8', 'C17.9', 'C18.0', 'C18.1', 'C18.2', 'C18.3', 'C18.4', 'C18.5', 'C18.6', 'C18.7', 'C18.8', 'C18.9', 'C19', 'C20', 'C21.0', 'C21.1', 'C21.2', 'C21.8', 'C22.0', 'C22.1', 'C22.2', 'C22.3', 'C22.4', 'C22.5', 'C22.6', 'C22.7', 'C22.8', 'C22.9', 'C23', 'C24.0', 'C24.1', 'C24.8', 'C24.9', 'C25.0', 'C25.1', 'C25.2', 'C25.3', 'C25.4', 'C25.7', 'C25.8', 'C25.9', 'C26.0', 'C26.1', 'C26.8', 'C26.9') THEN 2
          WHEN icd_code IN ('I50.1', 'I50.20', 'I50.21', 'I50.22', 'I50.23', 'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.40', 'I50.41', 'I50.42', 'I50.43', 'I50.9') THEN 1
          WHEN icd_code IN ('J44.0', 'J44.1', 'J44.9', 'J43.0', 'J43.1', 'J43.2', 'J43.8', 'J43.9', 'J42', 'J41.0', 'J41.1', 'J41.8', 'J40', 'J47.0', 'J47.1', 'J47.9', 'J60', 'J61', 'J62.0', 'J62.8', 'J63.0', 'J63.1', 'J63.2', 'J63.3', 'J63.4', 'J63.5', 'J63.6', 'J63.8', 'J63.9', 'J64', 'J65', 'J66.0', 'J66.1', 'J66.2', 'J66.8', 'J67.0', 'J67.1', 'J67.2', 'J67.3', 'J67.4', 'J67.5', 'J67.6', 'J67.7', 'J67.8', 'J67.9', 'J68.0', 'J68.1', 'J68.2', 'J68.3', 'J68.4', 'J68.9', 'J69.0', 'J69.1', 'J69.2', 'J69.8', 'J70.0', 'J70.1', 'J70.2', 'J70.3', 'J70.4', 'J70.8', 'J70.9') THEN 1
          WHEN icd_code IN ('E11.00', 'E11.01', 'E11.10', 'E11.11', 'E11.21', 'E11.22', 'E11.29', 'E11.311', 'E11.319', 'E11.321', 'E11.329', 'E11.331', 'E11.339', 'E11.341', 'E11.349', 'E11.351', 'E11.359', 'E11.36', 'E11.37X11', 'E11.37X19', 'E11.37X21', 'E11.37X29', 'E11.39', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49', 'E11.51', 'E11.59', 'E11.610', 'E11.618', 'E11.620', 'E11.621', 'E11.622', 'E11.628', 'E11.630', 'E11.638', 'E11.641', 'E11.649', 'E11.65', 'E11.69', 'E11.8', 'E11.9') THEN 1
          WHEN icd_code IN ('N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9') THEN 2
          WHEN icd_code IN ('G30.0', 'G30.1', 'G30.8', 'G30.9', 'G31.01', 'G31.02', 'G31.03', 'G31.04', 'G31.09', 'G31.1', 'G31.81', 'G31.82', 'G31.83', 'G31.84', 'G31.85', 'G31.89', 'G31.9') THEN 1
          WHEN icd_code IN ('I69.010', 'I69.011', 'I69.012', 'I69.013', 'I69.014', 'I69.015', 'I69.016', 'I69.017', 'I69.018', 'I69.019', 'I69.020', 'I69.021', 'I69.022', 'I69.023', 'I69.024', 'I69.025', 'I69.026', 'I69.027', 'I69.028', 'I69.029', 'I69.030', 'I69.031', 'I69.032', 'I69.033', 'I69.034', 'I69.035', 'I69.036', 'I69.037', 'I69.038', 'I69.039', 'I69.090', 'I69.091', 'I69.092', 'I69.093', 'I69.094', 'I69.095', 'I69.096', 'I69.097', 'I69.098', 'I69.1', 'I69.2', 'I69.3', 'I69.8', 'I69.9') THEN 1
          WHEN icd_code IN ('F01.50', 'F01.51', 'F02.80', 'F02.81', 'F03.90', 'F03.91', 'F05', 'F06.0', 'F06.1', 'F06.2', 'F06.3', 'F06.4', 'F06.8', 'F07.0', 'F07.81', 'F07.89', 'F07.9', 'F10.10', 'F10.11', 'F10.120', 'F10.121', 'F10.129', 'F10.14', 'F10.150', 'F10.151', 'F10.159', 'F10.180', 'F10.181', 'F10.182', 'F10.188', 'F10.19', 'F10.20', 'F10.21', 'F10.220', 'F10.221', 'F10.229', 'F10.230', 'F10.231', 'F10.232', 'F10.239', 'F10.24', 'F10.250', 'F10.251', 'F10.259', 'F10.26', 'F10.27', 'F10.280', 'F10.281', 'F10.282', 'F10.288', 'F10.29', 'F10.90', 'F10.91', 'F10.920', 'F10.921', 'F10.929', 'F10.93', 'F10.94', 'F10.950', 'F10.951', 'F10.959', 'F10.96', 'F10.97', 'F10.980', 'F10.981', 'F10.982', 'F10.988', 'F10.99') THEN 1
          WHEN icd_code IN ('F01.50', 'F01.51', 'F02.80', 'F02.81', 'F03.90', 'F03.91', 'F05', 'F06.0', 'F06.1', 'F06.2', 'F06.3', 'F06.4', 'F06.8', 'F07.0', 'F07.81', 'F07.89', 'F07.9', 'F10.10', 'F10.11', 'F10.120', 'F10.121', 'F10.129', 'F10.14', 'F10.150', 'F10.151', 'F10.159', 'F10.180', 'F10.181', 'F10.182', 'F10.188', 'F10.19', 'F10.20', 'F10.21', 'F10.220', 'F10.221', 'F10.229', 'F10.230', 'F10.231', 'F10.232', 'F10.239', 'F10.24', 'F10.250', 'F10.251', 'F10.259', 'F10.26', 'F10.27', 'F10.280', 'F10.281', 'F10.282', 'F10.288', 'F10.29', 'F10.90', 'F10.91', 'F10.920', 'F10.921', 'F10.929', 'F10.93', 'F10.94', 'F10.950', 'F10.951', 'F10.959', 'F10.96', 'F10.97', 'F10.980', 'F10.981', 'F10.982', 'F10.988', 'F10.99') THEN 1
          ELSE 0
        END) AS cci_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN ich_patients ip ON d.subject_id = ip.subject_id AND d.hadm_id = ip.hadm_id
  GROUP BY subject_id, hadm_id
),

-- Combine with patient data and calculate quintiles
patient_data AS (
  SELECT
    ip.*,
    c.cci_score,
    NTILE(5) OVER (ORDER BY c.cci_score) AS risk_quintile
  FROM ich_patients ip
  JOIN cci_scores c ON ip.subject_id = c.subject_id AND ip.hadm_id = c.hadm_id
),

-- Identify major complications (simplified - using procedure codes)
major_complications AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE icd_code IN (
    -- Example major complication codes (this should be expanded)
    '00.11', '00.12', '00.13', '00.14', '00.15', '00.16', '00.17', '00.18', '00.19',
    '00.21', '00.22', '00.23', '00.24', '00.25', '00.26', '00.27', '00.28', '00.29',
    '00.31', '00.32', '00.33', '00.34', '00.35', '00.36', '00.37', '00.38', '00.39'
  )
)

-- Final aggregation by quintile
SELECT
  risk_quintile,
  COUNT(*) AS n,
  ROUND(100 * SUM(died_within_30_days) / COUNT(*), 1) AS mortality_30day_pct,
  ROUND(100 * SUM(CASE WHEN mc.subject_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS major_complication_pct,
  ROUND(PERCENTILE_CONT(CASE WHEN died_within_30_days = 0 THEN los ELSE NULL END, 0.5) OVER(), 1) AS median_survivor_los
FROM patient_data pd
LEFT JOIN major_complications mc ON pd.subject_id = mc.subject_id AND pd.hadm_id = mc.hadm_id
GROUP BY risk_quintile
ORDER BY risk_quintile;