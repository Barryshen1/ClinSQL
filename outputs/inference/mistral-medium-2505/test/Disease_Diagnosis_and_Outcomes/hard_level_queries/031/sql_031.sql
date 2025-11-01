WITH
-- Define asthma exacerbation ICD codes (ICD-10 J45.x)
asthma_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
  AND icd_code LIKE 'J45%'
),

-- Get female patients aged 85-95 with asthma exacerbation admissions
asthma_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN asthma_codes ac
    ON d.icd_code = ac.icd_code AND d.icd_version = 10
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 85 AND 95
    AND a.admission_type != 'NEWBORN'  -- Exclude newborn admissions
),

-- Calculate Charlson Comorbidity Index (CCI) for each patient
cci_scores AS (
  SELECT
    subject_id,
    hadm_id,
    -- Calculate CCI score (simplified version - weights would need to be added)
    SUM(CASE
      WHEN d.icd_code IN ('I21', 'I22', 'I252') THEN 1  -- Myocardial infarction
      WHEN d.icd_code IN ('I63', 'I64') THEN 1         -- Cerebrovascular disease
      WHEN d.icd_code IN ('E109', 'E119', 'E139') THEN 1 -- Diabetes without complications
      -- Add more conditions with appropriate weights
      ELSE 0
    END) AS cci_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.subject_id IN (SELECT subject_id FROM asthma_patients)
    AND d.icd_version = 10  -- Using ICD-10 codes
  GROUP BY subject_id, hadm_id
),

-- Assign quartiles based on CCI scores
quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    cci_score,
    NTILE(4) OVER (ORDER BY cci_score) AS quartile
  FROM cci_scores
),

-- Identify cardiovascular complications
cv_complications AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN d.icd_code IN ('I21', 'I22', 'I252', 'I63', 'I64') THEN 1 ELSE 0 END) AS has_cv_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.subject_id IN (SELECT subject_id FROM asthma_patients)
    AND d.icd_version = 10
  GROUP BY d.subject_id, d.hadm_id
),

-- Identify neurologic complications
neuro_complications AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN d.icd_code IN ('I63', 'I64', 'G45', 'G46') THEN 1 ELSE 0 END) AS has_neuro_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.subject_id IN (SELECT subject_id FROM asthma_patients)
    AND d.icd_version = 10
  GROUP BY d.subject_id, d.hadm_id
)

-- Final result with stratification by quartile
SELECT
  q.quartile,
  COUNT(DISTINCT q.subject_id) AS patient_count,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality,
  SUM(cv.has_cv_complication) AS cv_complications,
  SUM(neuro.has_neuro_complication) AS neuro_complications,
  ROUND(SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT q.subject_id), 2) AS mortality_rate,
  ROUND(SUM(cv.has_cv_complication) * 100.0 / COUNT(DISTINCT q.subject_id), 2) AS cv_complication_rate,
  ROUND(SUM(neuro.has_neuro_complication) * 100.0 / COUNT(DISTINCT q.subject_id), 2) AS neuro_complication_rate
FROM quartiles q
JOIN asthma_patients a
  ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
LEFT JOIN cv_complications cv
  ON q.subject_id = cv.subject_id AND q.hadm_id = cv.hadm_id
LEFT JOIN neuro_complications neuro
  ON q.subject_id = neuro.subject_id AND q.hadm_id = neuro.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;