WITH
-- Define PE patients (ICD-10 codes for pulmonary embolism: I26.*)
pe_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'I26%'
),

-- Define control group (same age range, female, no PE)
control_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.subject_id NOT IN (SELECT subject_id FROM pe_patients)
),

-- Calculate Charlson Comorbidity Index (CCI) for each patient
comorbidity_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
      WHEN icd_code IN ('I21', 'I22', 'I252') THEN 1 -- Myocardial infarction
      WHEN icd_code IN ('I50', 'I110', 'I130', 'I132') THEN 1 -- Congestive heart failure
      WHEN icd_code IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') THEN 1 -- Cerebrovascular disease
      WHEN icd_code IN ('E10', 'E11', 'E12', 'E13', 'E14') THEN 1 -- Diabetes
      WHEN icd_code IN ('C00', 'C01', 'C02', 'C03', 'C04', 'C05', 'C06', 'C07', 'C08', 'C09',
                        'C10', 'C11', 'C12', 'C13', 'C14', 'C15', 'C16', 'C17', 'C18', 'C19',
                        'C20', 'C21', 'C22', 'C23', 'C24', 'C25', 'C26') THEN 1 -- Malignancy
      WHEN icd_code IN ('J440', 'J441', 'J449') THEN 1 -- COPD
      WHEN icd_code IN ('N18', 'N19') THEN 1 -- Chronic kidney disease
      WHEN icd_code IN ('K70', 'K71', 'K72', 'K73', 'K74', 'K75', 'K76') THEN 1 -- Liver disease
      WHEN icd_code IN ('F01', 'F02', 'F03', 'F051', 'G30', 'G311') THEN 1 -- Dementia
      WHEN icd_code IN ('M05', 'M06', 'M08', 'M10', 'M12', 'M13') THEN 1 -- Rheumatic disease
      WHEN icd_code IN ('D610', 'D611', 'D612', 'D613', 'D618', 'D619') THEN 1 -- Coagulopathy
      WHEN icd_code IN ('E66', 'E67', 'E68') THEN 1 -- Obesity
      ELSE 0
    END) AS cci_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),

-- High comorbidity burden (CCI >= 3)
high_comorbidity_patients AS (
  SELECT subject_id, hadm_id
  FROM comorbidity_scores
  WHERE cci_score >= 3
),

-- Final PE group with high comorbidity
pe_high_comorbidity AS (
  SELECT p.subject_id, p.hadm_id
  FROM pe_patients p
  JOIN high_comorbidity_patients h ON p.subject_id = h.subject_id AND p.hadm_id = h.hadm_id
),

-- 30-day mortality
mortality_30day AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE
      WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- Cardio/neurologic complications
complications AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN icd_code LIKE 'I%' THEN 1 ELSE 0 END) AS has_cardio_complication,
    MAX(CASE WHEN icd_code LIKE 'G%' OR icd_code LIKE 'I6%' THEN 1 ELSE 0 END) AS has_neuro_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),

-- Length of stay
los AS (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS length_of_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Combined data for analysis
combined_data AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    'PE' AS group_type,
    c.cci_score,
    m.died_within_30days,
    com.has_cardio_complication,
    com.has_neuro_complication,
    l.length_of_stay
  FROM pe_high_comorbidity p
  JOIN comorbidity_scores c ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  JOIN mortality_30day m ON p.subject_id = m.subject_id AND p.hadm_id = m.hadm_id
  JOIN complications com ON p.subject_id = com.subject_id AND p.hadm_id = com.hadm_id
  JOIN los l ON p.subject_id = l.subject_id AND p.hadm_id = l.hadm_id

  UNION ALL

  SELECT
    c.subject_id,
    c.hadm_id,
    'Control' AS group_type,
    cs.cci_score,
    m.died_within_30days,
    com.has_cardio_complication,
    com.has_neuro_complication,
    l.length_of_stay
  FROM control_patients c
  JOIN comorbidity_scores cs ON c.subject_id = cs.subject_id AND c.hadm_id = cs.hadm_id
  JOIN mortality_30day m ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
  JOIN complications com ON c.subject_id = com.subject_id AND c.hadm_id = com.hadm_id
  JOIN los l ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
),

-- Calculate percentiles for each group
pe_percentiles AS (
  SELECT
    PERCENTILE_CONT(length_of_stay, 0.25) OVER() AS q1_los,
    PERCENTILE_CONT(length_of_stay, 0.5) OVER() AS median_los,
    PERCENTILE_CONT(length_of_stay, 0.75) OVER() AS q3_los
  FROM combined_data
  WHERE group_type = 'PE'
  LIMIT 1
),

control_percentiles AS (
  SELECT
    PERCENTILE_CONT(length_of_stay, 0.25) OVER() AS q1_los,
    PERCENTILE_CONT(length_of_stay, 0.5) OVER() AS median_los,
    PERCENTILE_CONT(length_of_stay, 0.75) OVER() AS q3_los
  FROM combined_data
  WHERE group_type = 'Control'
  LIMIT 1
)

-- Final analysis
SELECT
  group_type,
  AVG(cci_score) AS mean_comorbidity_score,
  AVG(died_within_30days) AS mortality_30day_rate,
  AVG(has_cardio_complication) AS cardio_complication_rate,
  AVG(has_neuro_complication) AS neuro_complication_rate,
  AVG(length_of_stay) AS avg_length_of_stay,
  CASE
    WHEN group_type = 'PE' THEN (SELECT median_los FROM pe_percentiles)
    ELSE (SELECT median_los FROM control_percentiles)
  END AS median_los,
  CASE
    WHEN group_type = 'PE' THEN (SELECT q1_los FROM pe_percentiles)
    ELSE (SELECT q1_los FROM control_percentiles)
  END AS q1_los,
  CASE
    WHEN group_type = 'PE' THEN (SELECT q3_los FROM pe_percentiles)
    ELSE (SELECT q3_los FROM control_percentiles)
  END AS q3_los
FROM combined_data
GROUP BY group_type;