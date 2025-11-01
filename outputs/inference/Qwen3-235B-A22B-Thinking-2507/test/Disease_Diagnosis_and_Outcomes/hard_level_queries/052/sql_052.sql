WITH 
-- Step 1: Define COPD exacerbation cohort (female, 75-85, primary diagnosis)
patients_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_year,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND d.icd_code IN ('J44.0', 'J44.1', '491.21', '491.22', '492.21', '492.22', '496.21', '496.22')
    )
),

-- Step 2: Compute Charlson Comorbidity Index (CCI) for cohort
cci_mapping AS (
  SELECT icd_code, condition, weight
  FROM UNNEST([
    STRUCT('410' AS icd_code, 'mi' AS condition, 1 AS weight), -- Myocardial infarction
    STRUCT('412', 'mi', 1),
    STRUCT('I21', 'mi', 1),
    STRUCT('I22', 'mi', 1),
    STRUCT('428', 'chf', 1), -- Congestive heart failure
    STRUCT('I50', 'chf', 1),
    STRUCT('430', 'cerebrovascular', 1), -- Cerebrovascular disease
    STRUCT('431', 'cerebrovascular', 1),
    STRUCT('432', 'cerebrovascular', 1),
    STRUCT('433', 'cerebrovascular', 1),
    STRUCT('434', 'cerebrovascular', 1),
    STRUCT('435', 'cerebrovascular', 1),
    STRUCT('436', 'cerebrovascular', 1),
    STRUCT('I60', 'cerebrovascular', 1),
    STRUCT('I61', 'cerebrovascular', 1),
    STRUCT('I62', 'cerebrovascular', 1),
    STRUCT('I63', 'cerebrovascular', 1),
    STRUCT('I64', 'cerebrovascular', 1),
    STRUCT('I65', 'cerebrovascular', 1),
    STRUCT('I66', 'cerebrovascular', 1),
    STRUCT('490', 'copd', 1), -- Chronic pulmonary disease (COPD)
    STRUCT('491', 'copd', 1),
    STRUCT('492', 'copd', 1),
    STRUCT('493', 'copd', 1),
    STRUCT('494', 'copd', 1),
    STRUCT('495', 'copd', 1),
    STRUCT('496', 'copd', 1),
    STRUCT('J40', 'copd', 1),
    STRUCT('J41', 'copd', 1),
    STRUCT('J42', 'copd', 1),
    STRUCT('J43', 'copd', 1),
    STRUCT('J44', 'copd', 1),
    STRUCT('J45', 'copd', 1),
    STRUCT('J46', 'copd', 1),
    STRUCT('2500', 'diabetes', 1), -- Diabetes without complications
    STRUCT('2501', 'diabetes', 1),
    STRUCT('E100', 'diabetes', 1),
    STRUCT('E110', 'diabetes', 1),
    STRUCT('E120', 'diabetes', 1),
    STRUCT('E130', 'diabetes', 1),
    STRUCT('E140', 'diabetes', 1),
    STRUCT('2502', 'diabetes_comp', 2), -- Diabetes with complications
    STRUCT('2503', 'diabetes_comp', 2),
    STRUCT('2504', 'diabetes_comp', 2),
    STRUCT('2505', 'diabetes_comp', 2),
    STRUCT('2506', 'diabetes_comp', 2),
    STRUCT('2507', 'diabetes_comp', 2),
    STRUCT('2508', 'diabetes_comp', 2),
    STRUCT('2509', 'diabetes_comp', 2),
    STRUCT('E101', 'diabetes_comp', 2),
    STRUCT('E102', 'diabetes_comp', 2),
    STRUCT('E103', 'diabetes_comp', 2),
    STRUCT('E104', 'diabetes_comp', 2),
    STRUCT('E105', 'diabetes_comp', 2),
    STRUCT('E106', 'diabetes_comp', 2),
    STRUCT('E107', 'diabetes_comp', 2),
    STRUCT('E108', 'diabetes_comp', 2),
    STRUCT('E109', 'diabetes_comp', 2),
    STRUCT('E111', 'diabetes_comp', 2),
    STRUCT('E112', 'diabetes_comp', 2),
    STRUCT('E113', 'diabetes_comp', 2),
    STRUCT('E114', 'diabetes_comp', 2),
    STRUCT('E115', 'diabetes_comp', 2),
    STRUCT('E116', 'diabetes_comp', 2),
    STRUCT('E117', 'diabetes_comp', 2),
    STRUCT('E118', 'diabetes_comp', 2),
    STRUCT('E119', 'diabetes_comp', 2),
    STRUCT('E121', 'diabetes_comp', 2),
    STRUCT('E122', 'diabetes_comp', 2),
    STRUCT('E123', 'diabetes_comp', 2),
    STRUCT('E124', 'diabetes_comp', 2),
    STRUCT('E125', 'diabetes_comp', 2),
    STRUCT('E126', 'diabetes_comp', 2),
    STRUCT('E127', 'diabetes_comp', 2),
    STRUCT('E128', 'diabetes_comp', 2),
    STRUCT('E129', 'diabetes_comp', 2),
    STRUCT('E131', 'diabetes_comp', 2),
    STRUCT('E132', 'diabetes_comp', 2),
    STRUCT('E133', 'diabetes_comp', 2),
    STRUCT('E134', 'diabetes_comp', 2),
    STRUCT('E135', 'diabetes_comp', 2),
    STRUCT('E136', 'diabetes_comp', 2),
    STRUCT('E137', 'diabetes_comp', 2),
    STRUCT('E138', 'diabetes_comp', 2),
    STRUCT('E139', 'diabetes_comp', 2),
    STRUCT('E141', 'diabetes_comp', 2),
    STRUCT('E142', 'diabetes_comp', 2),
    STRUCT('E143', 'diabetes_comp', 2),
    STRUCT('E144', 'diabetes_comp', 2),
    STRUCT('E145', 'diabetes_comp', 2),
    STRUCT('E146', 'diabetes_comp', 2),
    STRUCT('E147', 'diabetes_comp', 2),
    STRUCT('E148', 'diabetes_comp', 2),
    STRUCT('E149', 'diabetes_comp', 2)
  ])
),
cci_scores AS (
  SELECT 
    hadm_id,
    SUM(weight) AS cci
  FROM (
    SELECT 
      d.hadm_id,
      m.condition,
      MAX(m.weight) AS weight  -- Take max weight per condition (avoids duplicates)
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    INNER JOIN cci_mapping m
      ON d.icd_code LIKE CONCAT(m.icd_code, '%')  -- Prefix match for ICD codes
    WHERE d.hadm_id IN (SELECT hadm_id FROM patients_cohort)
    GROUP BY d.hadm_id, m.condition
  )
  GROUP BY hadm_id
),

-- Step 3: Compute complications (ventilation, respiratory failure, sepsis)
complications AS (
  SELECT DISTINCT hadm_id
  FROM (
    -- Respiratory failure or sepsis (diagnoses)
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE icd_code IN ('J96.00', 'J96.01', 'J96.8', 'J96.9', 'A41.9', 'A41.51', 'A41.52')
    
    UNION DISTINCT
    
    -- Mechanical ventilation (procedureevents)
    SELECT p.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu`.procedureevents p
    INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items i
      ON p.itemid = i.itemid
    WHERE LOWER(i.label) LIKE '%ventilat%' 
       OR LOWER(i.label) LIKE '%intubat%'
  )
),

-- Step 4: Combine metrics and assign risk quartiles
metrics AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.dod,
    -- Age at admission
    EXTRACT(YEAR FROM c.admittime) - (c.anchor_year - c.anchor_age) AS age_at_admission,
    -- 90-day mortality flag
    CASE WHEN c.dod IS NOT NULL AND c.dod <= c.admittime + INTERVAL '90' DAY THEN 1 ELSE 0 END AS died_within_90,
    -- Hospital LOS (days)
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los,
    -- Complication flag
    IF(comp.hadm_id IS NOT NULL, 1, 0) AS complication_flag,
    -- CCI (default to 0 if no comorbidities)
    COALESCE(cci.cci, 0) AS cci
  FROM patients_cohort c
  LEFT JOIN complications comp ON c.hadm_id = comp.hadm_id
  LEFT JOIN cci_scores cci ON c.hadm_id = cci.hadm_id
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY cci) AS risk_quartile  -- Stratify by CCI quartiles
  FROM metrics
),

-- Step 5: Compute broader 75-85 female 90-day mortality (all patients, not just COPD)
broader_population AS (
  SELECT 
    COUNT(*) AS total,
    SUM(CASE WHEN p.dod IS NOT NULL AND p.dod <= a.admittime + INTERVAL '90' DAY THEN 1 ELSE 0 END) AS deaths
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 75 AND 85
),
broader_mortality AS (
  SELECT deaths / total AS broader_mortality_rate
  FROM broader_population
),

-- Step 6: Aggregate per quartile
aggregation AS (
  SELECT 
    risk_quartile,
    AVG(died_within_90) AS mortality_90d,
    AVG(complication_flag) AS complication_rate,
    APPROX_QUANTILES(IF(hospital_expire_flag = 0, los, NULL), 100)[OFFSET(50)] AS median_survivor_los
  FROM quartiles
  GROUP BY risk_quartile
)

-- Final output: quartile metrics + broader mortality rate
SELECT 
  a.risk_quartile,
  a.mortality_90d,
  a.complication_rate,
  a.median_survivor_los,
  b.broader_mortality_rate
FROM aggregation a
CROSS JOIN broader_mortality b
ORDER BY a.risk_quartile;