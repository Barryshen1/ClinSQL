WITH
-- Define pneumonia ICD codes (example: J18.9 for unspecified pneumonia)
pneumonia_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'J18.%'
),

-- Get male patients aged 73-83 with pneumonia
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN pneumonia_icd p_icd ON d.icd_code = p_icd.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.hospital_expire_flag IS NOT NULL
),

-- Calculate Charlson Comorbidity Index (more comprehensive)
comorbidity_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
      WHEN icd_code IN ('I10', 'I11.0', 'I11.9', 'I12.0', 'I12.9', 'I13.0', 'I13.1', 'I13.10', 'I13.11', 'I13.2', 'I13.9') THEN 1 -- Congestive Heart Failure
      WHEN icd_code IN ('I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9', 'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9', 'I25.2') THEN 1 -- Myocardial Infarction
      WHEN icd_code IN ('I63', 'I63.0', 'I63.1', 'I63.2', 'I63.3', 'I63.4', 'I63.5', 'I63.6', 'I63.8', 'I63.9') THEN 1 -- Cerebrovascular Disease
      WHEN icd_code IN ('E10.65', 'E10.69', 'E11.65', 'E11.69', 'E13.65', 'E13.69') THEN 1 -- Diabetes with complications
      WHEN icd_code IN ('J44.0', 'J44.1', 'J44.9') THEN 1 -- COPD
      WHEN icd_code IN ('C00.0', 'C00.1', 'C00.2', 'C00.3', 'C00.4', 'C00.5', 'C00.6', 'C00.8', 'C00.9') THEN 2 -- Metastatic cancer
      WHEN icd_code IN ('C77.0', 'C77.1', 'C77.2', 'C77.3', 'C77.4', 'C77.5', 'C77.8', 'C77.9') THEN 2 -- Metastatic cancer
      WHEN icd_code IN ('C78.0', 'C78.1', 'C78.2', 'C78.3', 'C78.4', 'C78.5', 'C78.6', 'C78.7', 'C78.8') THEN 2 -- Metastatic cancer
      WHEN icd_code IN ('C79.0', 'C79.1', 'C79.2', 'C79.3', 'C79.4', 'C79.5', 'C79.6', 'C79.7', 'C79.8', 'C79.9') THEN 2 -- Metastatic cancer
      WHEN icd_code IN ('C80.0', 'C80.1', 'C80.2') THEN 2 -- Metastatic cancer
      WHEN icd_code IN ('C97') THEN 2 -- Metastatic cancer
      WHEN icd_code IN ('I50.1', 'I50.20', 'I50.21', 'I50.22', 'I50.23', 'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.40', 'I50.41', 'I50.42', 'I50.43', 'I50.9') THEN 1 -- Heart Failure
      WHEN icd_code IN ('I25.10', 'I25.110', 'I25.111', 'I25.118', 'I25.119', 'I25.5', 'I25.6', 'I25.70', 'I25.71', 'I25.72', 'I25.73', 'I25.74', 'I25.75', 'I25.76', 'I25.79') THEN 1 -- CAD
      WHEN icd_code IN ('I70.20', 'I70.21', 'I70.22', 'I70.23', 'I70.24', 'I70.25', 'I70.26', 'I70.29', 'I70.9') THEN 1 -- PVD
      WHEN icd_code IN ('N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9') THEN 2 -- Renal Disease
      WHEN icd_code IN ('K70.0', 'K70.1', 'K70.2', 'K70.3', 'K70.4', 'K70.9', 'K73', 'K73.0', 'K73.1', 'K73.2', 'K73.8', 'K73.9', 'K74.0', 'K74.1', 'K74.2', 'K74.3', 'K74.4', 'K74.5', 'K74.6', 'K76.0', 'K76.2', 'K76.3', 'K76.4', 'K76.5', 'K76.6', 'K76.7', 'K76.8', 'K76.9') THEN 1 -- Liver Disease
      WHEN icd_code IN ('G30.0', 'G30.1', 'G30.8', 'G30.9', 'G31.01', 'G31.09', 'G31.1', 'G31.83', 'G31.84', 'G31.85', 'G31.89', 'G31.9') THEN 1 -- Dementia
      WHEN icd_code IN ('G82.20', 'G82.21', 'G82.22', 'G82.23', 'G82.24', 'G82.25', 'G82.26', 'G82.27', 'G82.28', 'G82.29', 'G82.3', 'G82.4', 'G82.50', 'G82.51', 'G82.52', 'G82.53', 'G82.54') THEN 2 -- Hemiplegia
      WHEN icd_code IN ('E10.65', 'E10.69', 'E11.65', 'E11.69', 'E13.65', 'E13.69') THEN 1 -- Diabetes with complications
      WHEN icd_code IN ('E10.9', 'E11.9', 'E13.9') THEN 1 -- Diabetes without complications
      WHEN icd_code IN ('E66.01', 'E66.9', 'E66.09', 'E66.1', 'E66.2', 'E66.3', 'E66.8', 'E66.9') THEN 1 -- Obesity
      WHEN icd_code IN ('F10.10', 'F10.11', 'F10.12', 'F10.13', 'F10.14', 'F10.15', 'F10.16', 'F10.17', 'F10.18', 'F10.19', 'F10.20', 'F10.21', 'F10.22', 'F10.23', 'F10.24', 'F10.25', 'F10.26', 'F10.27', 'F10.28', 'F10.29', 'F10.90', 'F10.91', 'F10.92', 'F10.93', 'F10.94', 'F10.95', 'F10.96', 'F10.97', 'F10.98', 'F10.99') THEN 1 -- Alcohol abuse
      WHEN icd_code IN ('F11.10', 'F11.11', 'F11.12', 'F11.13', 'F11.14', 'F11.15', 'F11.16', 'F11.17', 'F11.18', 'F11.19', 'F11.20', 'F11.21', 'F11.22', 'F11.23', 'F11.24', 'F11.25', 'F11.26', 'F11.27', 'F11.28', 'F11.29', 'F11.90', 'F11.91', 'F11.92', 'F11.93', 'F11.94', 'F11.95', 'F11.96', 'F11.97', 'F11.98', 'F11.99') THEN 1 -- Drug abuse
      WHEN icd_code IN ('F19.10', 'F19.11', 'F19.12', 'F19.13', 'F19.14', 'F19.15', 'F19.16', 'F19.17', 'F19.18', 'F19.19', 'F19.20', 'F19.21', 'F19.22', 'F19.23', 'F19.24', 'F19.25', 'F19.26', 'F19.27', 'F19.28', 'F19.29', 'F19.90', 'F19.91', 'F19.92', 'F19.93', 'F19.94', 'F19.95', 'F19.96', 'F19.97', 'F19.98', 'F19.99') THEN 1 -- Other substance abuse
      ELSE 0
    END) AS cci_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),

-- First calculate quartiles for all patients
comorbidity_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    cci_score,
    NTILE(4) OVER (ORDER BY cci_score DESC) AS quartile
  FROM comorbidity_scores
),

-- Then filter for top quartile
top_quartile_comorbidity AS (
  SELECT
    subject_id,
    hadm_id,
    cci_score
  FROM comorbidity_quartiles
  WHERE quartile = 1
),

-- Final cohort with top quartile comorbidity
final_cohort AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.hospital_expire_flag,
    c.dod,
    c.anchor_age,
    c.anchor_year,
    tqc.cci_score
  FROM cohort c
  JOIN top_quartile_comorbidity tqc ON c.subject_id = tqc.subject_id AND c.hadm_id = tqc.hadm_id
),

-- Calculate in-hospital mortality
mortality AS (
  SELECT
    COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) AS deaths,
    COUNT(*) AS total_patients,
    COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) / COUNT(*) AS mortality_rate
  FROM final_cohort
),

-- Calculate major complications (example: sepsis)
complications AS (
  SELECT
    COUNT(DISTINCT CASE WHEN icd_code LIKE 'A41.%' THEN d.subject_id END) AS sepsis_complications,
    COUNT(DISTINCT d.subject_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN icd_code LIKE 'A41.%' THEN d.subject_id END) / COUNT(DISTINCT d.subject_id) AS complication_rate
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN final_cohort fc ON d.subject_id = fc.subject_id AND d.hadm_id = fc.hadm_id
),

-- Calculate median survival days
survival AS (
  SELECT
    PERCENTILE_CONT(DATE_DIFF(COALESCE(deathtime, dischtime), admittime, DAY), 0.5) AS median_survival_days
  FROM final_cohort
)

-- Final results
SELECT
  'Composite Risk Percentile' AS metric,
  (SELECT COUNT(*) FROM final_cohort) AS cohort_size,
  (SELECT mortality_rate FROM mortality) AS in_hospital_mortality_rate,
  (SELECT complication_rate FROM complications) AS major_complication_rate,
  (SELECT median_survival_days FROM survival) AS median_survival_days;