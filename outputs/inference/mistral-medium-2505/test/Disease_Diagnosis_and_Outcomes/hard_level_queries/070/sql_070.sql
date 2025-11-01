WITH
-- Define DVT ICD-10 codes
dvt_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
  AND icd_code IN (
    'I82.40', 'I82.41', 'I82.42', 'I82.4Y', 'I82.4Z',
    'I82.50', 'I82.51', 'I82.52', 'I82.5Y', 'I82.5Z',
    'I82.60', 'I82.61', 'I82.62', 'I82.6Y', 'I82.6Z',
    'I82.90', 'I82.91', 'I82.92', 'I82.9Y', 'I82.9Z',
    'I26.90', 'I26.91', 'I26.92', 'I26.9Y', 'I26.9Z',
    'I80.20', 'I80.21', 'I80.22', 'I80.2Y', 'I80.2Z',
    'I80.30', 'I80.31', 'I80.32', 'I80.3Y', 'I80.3Z'
  )
),

-- Define major complication ICD-10 codes (now using diagnosis codes)
complication_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
  AND icd_code IN (
    -- Hemorrhage
    'I62.9', 'I61.9', 'I60.9',
    -- Pulmonary embolism
    'I26.9',
    -- Infections
    'A41.9', 'J15.9', 'T81.4'
  )
),

-- Calculate Charlson Comorbidity Index (simplified version)
cci_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
      WHEN icd_code IN ('I10', 'I11.0', 'I11.9', 'I12.0', 'I12.9', 'I13.0', 'I13.1', 'I13.10', 'I13.11', 'I13.2', 'I15.0', 'I15.1', 'I15.2', 'I15.8', 'I15.9') THEN 1 -- Congestive heart failure
      WHEN icd_code IN ('I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9', 'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9', 'I25.2') THEN 1 -- Myocardial infarction
      WHEN icd_code IN ('I63', 'I64', 'I65.0', 'I65.1', 'I65.2', 'I65.3', 'I65.8', 'I65.9', 'I66.0', 'I66.1', 'I66.2', 'I66.3', 'I66.4', 'I66.5', 'I66.6', 'I66.7', 'I66.8', 'I66.9') THEN 1 -- Cerebrovascular disease
      WHEN icd_code IN ('E10.65', 'E10.69', 'E11.65', 'E11.69', 'E13.65', 'E13.69') THEN 1 -- Diabetes with complications
      WHEN icd_code IN ('J44.0', 'J44.1', 'J44.9') THEN 1 -- COPD
      WHEN icd_code IN ('C00.0', 'C00.1', 'C00.2', 'C00.3', 'C00.4', 'C00.5', 'C00.6', 'C00.8', 'C00.9') THEN 2 -- Metastatic cancer
      WHEN icd_code IN ('N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9') THEN 2 -- Renal disease
      WHEN icd_code IN ('K70.0', 'K70.1', 'K70.2', 'K70.3', 'K70.4', 'K70.9') THEN 1 -- Mild liver disease
      WHEN icd_code IN ('K72.1', 'K72.9', 'K74.0', 'K74.1', 'K74.2', 'K74.3', 'K74.4', 'K74.5', 'K74.6') THEN 3 -- Moderate/severe liver disease
      WHEN icd_code IN ('F01.50', 'F01.51', 'F02.80', 'F02.81', 'F03.90', 'F03.91', 'F05', 'F06.7', 'F06.8', 'F07.0', 'F07.81', 'F07.89', 'F09') THEN 1 -- Dementia
      WHEN icd_code IN ('G30.0', 'G30.1', 'G30.8', 'G30.9') THEN 1 -- Hemiplegia
      WHEN icd_code IN ('M05.0', 'M05.1', 'M05.2', 'M05.3', 'M05.4', 'M05.5', 'M05.6', 'M05.7', 'M05.8', 'M05.9') THEN 1 -- Rheumatoid arthritis
      WHEN icd_code IN ('B20', 'B21', 'B22', 'B23', 'B24') THEN 6 -- AIDS
      ELSE 0
    END) AS cci_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  GROUP BY subject_id, hadm_id
),

-- Calculate CCI percentiles
cci_percentiles AS (
  SELECT
    subject_id,
    hadm_id,
    cci_score,
    PERCENT_RANK() OVER (ORDER BY cci_score) AS cci_percentile
  FROM cci_scores
),

-- Get qualifying admissions (fixed ambiguous column reference)
qualifying_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    c.cci_score,
    c.cci_percentile,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN cci_percentiles c ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN dvt_codes dc ON d.icd_code = dc.icd_code  -- Fixed: qualified d.icd_code
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND c.cci_percentile > 0.75
  AND a.admittime IS NOT NULL
),

-- Calculate 30-day mortality
mortality AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30 THEN 1
      WHEN hospital_expire_flag = 1 AND dod IS NOT NULL AND TIMESTAMP_DIFF(dod, admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30_days
  FROM qualifying_admissions
),

-- Calculate major complications (now using diagnosis codes)
complications AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    MAX(CASE WHEN d.icd_code IN (SELECT icd_code FROM complication_codes) THEN 1 ELSE 0 END) AS has_major_complication
  FROM qualifying_admissions q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON q.subject_id = d.subject_id AND q.hadm_id = d.hadm_id
  GROUP BY q.subject_id, q.hadm_id
),

-- Calculate survival time for decedents
survival AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
      WHEN dod IS NOT NULL THEN TIMESTAMP_DIFF(dod, admittime, DAY)
      ELSE NULL
    END AS survival_days
  FROM qualifying_admissions
  WHERE deathtime IS NOT NULL OR dod IS NOT NULL
),

-- Calculate composite risk score (simplified)
risk_scores AS (
  SELECT
    subject_id,
    hadm_id,
    (anchor_age * 0.1) + (cci_score * 0.5) AS composite_score,
    NTILE(4) OVER (ORDER BY (anchor_age * 0.1) + (cci_score * 0.5)) AS score_quartile
  FROM qualifying_admissions
)

-- Final results
SELECT
  COUNT(DISTINCT q.subject_id) AS cohort_size,
  SUM(m.died_within_30_days) * 100.0 / COUNT(DISTINCT q.subject_id) AS percent_30day_mortality,
  SUM(c.has_major_complication) * 100.0 / COUNT(DISTINCT q.subject_id) AS percent_major_complications,
  PERCENTILE_CONT(s.survival_days, 0.5) OVER() AS median_survival_days,
  COUNT(DISTINCT CASE WHEN rs.score_quartile = 1 THEN q.subject_id END) AS quartile1_count,
  COUNT(DISTINCT CASE WHEN rs.score_quartile = 2 THEN q.subject_id END) AS quartile2_count,
  COUNT(DISTINCT CASE WHEN rs.score_quartile = 3 THEN q.subject_id END) AS quartile3_count,
  COUNT(DISTINCT CASE WHEN rs.score_quartile = 4 THEN q.subject_id END) AS quartile4_count
FROM qualifying_admissions q
LEFT JOIN mortality m ON q.subject_id = m.subject_id AND q.hadm_id = m.hadm_id
LEFT JOIN complications c ON q.subject_id = c.subject_id AND q.hadm_id = c.hadm_id
LEFT JOIN survival s ON q.subject_id = s.subject_id AND q.hadm_id = s.hadm_id
LEFT JOIN risk_scores rs ON q.subject_id = rs.subject_id AND q.hadm_id = rs.hadm_id;