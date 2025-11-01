WITH target_subject AS (
    SELECT 123456 AS subject_id
),
pe_codes AS (
  -- Pulmonary Embolism ICD Codes
  SELECT icd_code, icd_version
  FROM UNNEST([
    -- ICD-9
    '4151', '41511', '41513', '41519', 
    -- ICD-10
    'I26', 'I260', 'I269', 'I2690', 'I2692', 'I2693', 'I2699'
  ]) AS icd_code,
  UNNEST([9, 10]) AS icd_version
),
charlson_map AS (
  -- Simplified Charlson Mapping (Quan et al.)
  SELECT * FROM UNNEST([
    -- Myocardial Infarction
    STRUCT('410' AS icd_code, 9 AS icd_version, 1 AS weight),
    STRUCT('I21' AS icd_code, 10 AS icd_version, 1 AS weight),
    STRUCT('I22' AS icd_code, 10 AS icd_version, 1 AS weight),
    -- Congestive Heart Failure
    STRUCT('428' AS icd_code, 9 AS icd_version, 1 AS weight),
    STRUCT('I50' AS icd_code, 10 AS icd_version, 1 AS weight),
    -- ... (Add all other Charlson categories similarly)
    -- Example: Metastatic Solid Tumor (weight=6)
    STRUCT('199' AS icd_code, 9 AS icd_version, 6 AS weight),
    STRUCT('C77' AS icd_code, 10 AS icd_version, 6 AS weight),
    STRUCT('C78' AS icd_code, 10 AS icd_version, 6 AS weight),
    STRUCT('C79' AS icd_code, 10 AS icd_version, 6 AS weight),
    STRUCT('C80' AS icd_code, 10 AS icd_version, 6 AS weight)
  ])
),
base_cohort AS (
  -- Male patients aged 79-89 with PE
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime,
    p.dod,
    p.anchor_age,
    p.anchor_year,
    DATE_DIFF(DATE(a.admittime), DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN pe_codes 
    ON d.icd_code = pe_codes.icd_code 
    AND d.icd_version = pe_codes.icd_version
  WHERE 
    p.gender = 'M'
    AND DATE_DIFF(DATE(a.admittime), DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 79 AND 89
),
charlson AS (
  -- Calculate Charlson Comorbidity Index per admission
  SELECT 
    bc.subject_id, 
    bc.hadm_id,
    SUM(DISTINCT cm.weight) AS charlson_score
  FROM base_cohort bc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON bc.subject_id = d.subject_id AND bc.hadm_id = d.hadm_id
  JOIN charlson_map cm
    ON d.icd_code = cm.icd_code 
    AND d.icd_version = cm.icd_version
  GROUP BY bc.subject_id, bc.hadm_id
),
cohort_with_charlson AS (
  SELECT 
    bc.*, 
    COALESCE(c.charlson_score, 0) AS charlson_score
  FROM base_cohort bc
  LEFT JOIN charlson c
    ON bc.subject_id = c.subject_id AND bc.hadm_id = c.hadm_id
),
top_quartile AS (
  -- Identify top-quartile CCI threshold
  SELECT 
    APPROX_QUANTILES(charlson_score, 4)[OFFSET(3)] AS cci_q3
  FROM cohort_with_charlson
),
subgroup AS (
  -- Patients in top-quartile comorbidity
  SELECT *
  FROM cohort_with_charlson
  WHERE charlson_score >= (SELECT cci_q3 FROM top_quartile)
),
complications AS (
  -- Cardiac/Neuro complications (new during admission)
  SELECT 
    s.hadm_id,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code IN ('410','428','4275')) 
        OR (d.icd_version = 10 AND d.icd_code IN ('I21','I22','I50','I46')) 
        THEN 1 ELSE 0 
    END) AS cardiac_complication,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code IN ('430','431','432','433','434','436','7803')) 
        OR (d.icd_version = 10 AND d.icd_code IN ('I60','I61','I62','I63','I64','G40','R56')) 
        THEN 1 ELSE 0 
    END) AS neuro_complication
  FROM subgroup s
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON s.hadm_id = d.hadm_id
  GROUP BY s.hadm_id
),
subgroup_outcomes AS (
  SELECT 
    -- 30-day mortality
    COUNTIF(
      (deathtime IS NOT NULL AND DATE_DIFF(DATE(deathtime), DATE(admittime), DAY) <= 30) OR
      (dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 30)
    ) / COUNT(*) AS mortality_30d,
    -- Cardiac complication rate
    AVG(cardiac_complication) AS cardiac_complication_rate,
    -- Neurologic complication rate
    AVG(neuro_complication) AS neuro_complication_rate,
    -- Median survival days (decedents only)
    APPROX_QUANTILES(
      CASE WHEN COALESCE(deathtime, dod) IS NOT NULL 
           THEN DATE_DIFF(DATE(COALESCE(deathtime, dod)), DATE(admittime), DAY) 
           ELSE NULL END, 
      100
    )[OFFSET(50)] AS median_survival_days
  FROM subgroup s
  LEFT JOIN complications c ON s.hadm_id = c.hadm_id
),
target_patient AS (
  -- Charlson score and percentile for the specific patient
  SELECT 
    charlson_score,
    PERCENT_RANK() OVER (ORDER BY charlson_score) AS composite_risk_percentile
  FROM subgroup
  WHERE subject_id = (SELECT subject_id FROM target_subject)
)
-- Final Output
SELECT 
  (SELECT composite_risk_percentile FROM target_patient) AS composite_risk_percentile,
  (SELECT charlson_score FROM target_patient) AS composite_risk_score,
  so.*
FROM subgroup_outcomes so;