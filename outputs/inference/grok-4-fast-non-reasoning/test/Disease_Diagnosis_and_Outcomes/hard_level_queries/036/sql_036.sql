WITH pneumonia_codes AS (
  -- Define pneumonia via ICD-10 titles
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = '10' 
    AND LOWER(long_title) LIKE '%pneumonia%'
),

-- Standard Charlson Comorbidity Index ICD-10 mappings (weights) - fuller list
charlson_weights AS (
  SELECT 'I21' AS icd_code, 1 AS weight UNION ALL  -- MI
  SELECT 'I22', 1 UNION ALL
  SELECT 'I25.2', 1 UNION ALL
  SELECT 'I09.9', 1 UNION ALL  -- CHF (partial)
  SELECT 'I11.0', 1 UNION ALL
  SELECT 'I13.0', 1 UNION ALL
  SELECT 'I13.2', 1 UNION ALL
  SELECT 'I42.0', 1 UNION ALL
  SELECT 'I42.5', 1 UNION ALL
  SELECT 'I42.6', 1 UNION ALL
  SELECT 'I42.7', 1 UNION ALL
  SELECT 'I43', 1 UNION ALL
  SELECT 'I50', 1 UNION ALL
  SELECT 'I26', 1 UNION ALL  -- PVD
  SELECT 'I70', 1 UNION ALL
  SELECT 'I71.4', 1 UNION ALL
  SELECT 'I73.9', 1 UNION ALL
  SELECT 'I79.0', 1 UNION ALL
  SELECT 'I82.8', 1 UNION ALL
  SELECT 'F02', 1 UNION ALL  -- Dementia
  SELECT 'F03', 1 UNION ALL
  SELECT 'G30', 1 UNION ALL
  SELECT 'J44', 1 UNION ALL  -- COPD
  SELECT 'J45', 1 UNION ALL
  SELECT 'J46', 1 UNION ALL
  SELECT 'J40', 1 UNION ALL
  SELECT 'J41', 1 UNION ALL
  SELECT 'J42', 1 UNION ALL
  SELECT 'J43', 1 UNION ALL
  SELECT 'C00', 2 UNION ALL  -- Malignancy (solid)
  SELECT 'C97', 2 UNION ALL
  SELECT 'E10', 1 UNION ALL  -- Diabetes
  SELECT 'E11', 1 UNION ALL
  SELECT 'E13', 1 UNION ALL
  SELECT 'N18', 2  -- ESRD (partial; add more as needed)
),

base_cohort AS (
  -- Patients: males, age 73-83 with any pneumonia admission
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN pneumonia_codes pc ON d.icd_code = pc.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND d.icd_version = '10'  -- Focus on ICD-10 for consistency
),

cci_scores AS (
  -- Calculate CCI per admission
  SELECT bc.*, COALESCE(SUM(cw.weight), 0) AS cci_score
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON bc.hadm_id = diag.hadm_id AND bc.subject_id = diag.subject_id
  LEFT JOIN charlson_weights cw ON (diag.icd_version = '10' AND diag.icd_code LIKE cw.icd_code || '%') 
    OR (diag.icd_version = '9' AND cw.icd_code IN ('250', '410', '585'))
  GROUP BY bc.subject_id, bc.hadm_id, bc.admittime, bc.dischtime, bc.hospital_expire_flag
),

top_quartile_cci AS (
  SELECT 
    PERCENTILE_CONT(0.75, cci_score) OVER() AS cci_threshold
  FROM cci_scores
),

high_comorbidity_cohort AS (
  SELECT cs.*
  FROM cci_scores cs, top_quartile_cci tq
  WHERE cs.cci_score >= tq.cci_threshold
),

-- Major complications: secondary diagnoses for AKI, sepsis, resp failure, MI
complication_codes AS (
  SELECT 'N17' AS icd_code, '10' AS version UNION ALL  -- AKI
  SELECT 'A40', '10' UNION ALL  -- Sepsis (partial)
  SELECT 'A41', '10' UNION ALL
  SELECT 'J96', '10' UNION ALL  -- Resp failure
  SELECT 'I21', '10'  -- MI
  -- Add ICD-9: e.g., SELECT '585', '9' UNION ALL ...
),

complications AS (
  SELECT hcc.hadm_id,
    MAX(CASE WHEN diag.seq_num > 1 AND comp.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_major_complication
  FROM high_comorbidity_cohort hcc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON hcc.hadm_id = diag.hadm_id
  LEFT JOIN complication_codes comp ON diag.icd_code LIKE comp.icd_code || '%' AND diag.icd_version = comp.version
  GROUP BY hcc.hadm_id
),

-- Cohort metrics
metrics AS (
  SELECT 
    COUNT(*) AS cohort_size,
    SUM(hcc.hospital_expire_flag) AS num_deaths,
    (SUM(hcc.hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_pct
  FROM high_comorbidity_cohort hcc
),

-- Median survival days (LOS for deaths only)
survival_metrics AS (
  SELECT 
    PERCENTILE_CONT(0.5) OVER (ORDER BY DATE_DIFF(PARSE_DATETIME('%Y-%m-%d %H:%M:%S', dischtime), PARSE_DATETIME('%Y-%m-%d %H:%M:%S', admittime), DAY)) AS median_survival_days
  FROM high_comorbidity_cohort
  WHERE hospital_expire_flag = 1
),

-- Composite risk: mortality (1 if died) + complication flag (0/1)
cohort_composites AS (
  SELECT 
    hcc.hadm_id,
    hcc.hospital_expire_flag + COALESCE(comp.has_major_complication, 0) AS composite_score
  FROM high_comorbidity_cohort hcc
  LEFT JOIN complications comp ON hcc.hadm_id = comp.hadm_id
),

composite_risk AS (
  SELECT 
    PERCENT_RANK() OVER (ORDER BY composite_score) * 100 AS risk_percentile,
    composite_score
  FROM cohort_composites
),

-- For target patient (assumed composite=0, low risk): percentile = avg % of cohort with higher score
patient_percentile AS (
  SELECT 
    (COUNTIF(composite_score > 0) * 100.0 / COUNT(*)) AS patient_composite_percentile_if_low_risk
  FROM cohort_composites
)

SELECT 
  m.mortality_pct,
  (SUM(comp.has_major_complication) * 100.0 / m.cohort_size) AS complication_pct,
  s.median_survival_days,
  p.patient_composite_percentile_if_low_risk AS patient_risk_percentile,
  AVG(c.composite_score) AS avg_composite_score
FROM metrics m
CROSS JOIN survival_metrics s
CROSS JOIN patient_percentile p
LEFT JOIN complications comp ON 1=1  -- For complication count
LEFT JOIN cohort_composites c ON 1=1  -- For avg composite
GROUP BY m.mortality_pct, m.cohort_size, s.median_survival_days, p.patient_composite_percentile_if_low_risk;