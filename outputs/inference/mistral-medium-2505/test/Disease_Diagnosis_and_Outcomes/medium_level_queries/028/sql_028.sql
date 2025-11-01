WITH
-- Get male patients aged 43-53 at admission
patient_demo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    EXTRACT(YEAR FROM CURRENT_DATE()) - anchor_year + anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND (EXTRACT(YEAR FROM CURRENT_DATE()) - anchor_year + anchor_age) BETWEEN 43 AND 53
),

-- Get first HF admission for each patient
first_hf_admission AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_seq
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN (
      'I500', 'I501', 'I509', 'I110', 'I130', 'I132'  -- HF ICD-10 codes
    )
    AND a.hospital_expire_flag IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Calculate Charlson Comorbidity Index (simplified version)
comorbidity_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
      WHEN icd_code IN ('I500', 'I501', 'I509') THEN 1  -- HF
      WHEN icd_code IN ('E1165', 'E1164', 'E1169') THEN 1  -- Diabetes with complications
      WHEN icd_code IN ('I2510', 'I2511', 'I2519') THEN 1  -- CAD
      WHEN icd_code IN ('I630', 'I631', 'I632', 'I633', 'I634', 'I635', 'I636', 'I638', 'I639') THEN 1  -- Stroke
      WHEN icd_code IN ('J440', 'J441', 'J449') THEN 1  -- COPD
      WHEN icd_code IN ('N181', 'N182', 'N183', 'N184', 'N185', 'N186', 'N189') THEN 2  -- CKD
      WHEN icd_code IN ('C000', 'C001', 'C002', 'C003', 'C004', 'C005', 'C006', 'C007', 'C008', 'C009') THEN 2  -- Metastatic cancer
      ELSE 0
    END) AS cci_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    subject_id, hadm_id
),

-- Categorize comorbidity burden
comorbidity_categories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN cci_score <= 1 THEN 'low'
      WHEN cci_score BETWEEN 2 AND 3 THEN 'medium'
      ELSE 'high'
    END AS comorbidity_burden
  FROM
    comorbidity_scores
),

-- Get LOS quartiles
los_quartiles AS (
  SELECT
    hadm_id,
    los_days,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM
    first_hf_admission
  WHERE
    admission_seq = 1  -- Only first HF admission
)

-- Final result with mortality stratified by LOS quartile and comorbidity burden
SELECT
  c.comorbidity_burden,
  l.los_quartile,
  COUNT(*) AS patient_count,
  SUM(CASE WHEN f.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(SUM(CASE WHEN f.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_percentage
FROM
  first_hf_admission f
JOIN
  patient_demo p ON f.subject_id = p.subject_id
JOIN
  comorbidity_categories c ON f.subject_id = c.subject_id AND f.hadm_id = c.hadm_id
JOIN
  los_quartiles l ON f.hadm_id = l.hadm_id
WHERE
  f.admission_seq = 1  -- Only first HF admission
GROUP BY
  c.comorbidity_burden,
  l.los_quartile
ORDER BY
  c.comorbidity_burden,
  l.los_quartile;