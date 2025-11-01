WITH charlson_weights AS (
  -- Defines Quan et al. Charlson comorbidity conditions, weights, and ICD code prefixes
  SELECT * FROM UNNEST([
    -- Weight 1
    STRUCT('MI' AS condition, 1 AS weight, '410' AS icd_prefix, 9 AS icd_version), STRUCT('MI', 1, '412', 9), STRUCT('MI', 1, 'I21', 10), STRUCT('MI', 1, 'I22', 10),
    STRUCT('CHF', 1, '428', 9), STRUCT('CHF', 1, 'I50', 10),
    STRUCT('PVD', 1, '443.9', 9), STRUCT('PVD', 1, '441', 9), STRUCT('PVD', 1, '785.4', 9), STRUCT('PVD', 1, 'V43.4', 9), STRUCT('PVD', 1, 'I70', 10), STRUCT('PVD', 1, 'I71', 10), STRUCT('PVD', 1, 'I73', 10),
    STRUCT('CVD', 1, '430', 9), STRUCT('CVD', 1, '431', 9), STRUCT('CVD', 1, '432', 9), STRUCT('CVD', 1, '433', 9), STRUCT('CVD', 1, '434', 9), STRUCT('CVD', 1, '435', 9), STRUCT('CVD', 1, '436', 9), STRUCT('CVD', 1, '437', 9), STRUCT('CVD', 1, '438', 9), STRUCT('CVD', 1, 'G45', 10), STRUCT('CVD', 1, 'G46', 10), STRUCT('CVD', 1, 'I60', 10), STRUCT('CVD', 1, 'I61', 10), STRUCT('CVD', 1, 'I62', 10), STRUCT('CVD', 1, 'I63', 10), STRUCT('CVD', 1, 'I64', 10), STRUCT('CVD', 1, 'I65', 10), STRUCT('CVD', 1, 'I66', 10), STRUCT('CVD', 1, 'I67', 10), STRUCT('CVD', 1, 'I68', 10), STRUCT('CVD', 1, 'I69', 10),
    STRUCT('Dementia', 1, '290', 9), STRUCT('Dementia', 1, 'F01', 10), STRUCT('Dementia', 1, 'F02', 10), STRUCT('Dementia', 1, 'F03', 10), STRUCT('Dementia', 1, 'G30', 10),
    STRUCT('Pulmonary', 1, '49', 9), STRUCT('Pulmonary', 1, '50', 9), STRUCT('Pulmonary', 1, 'J40', 10), STRUCT('Pulmonary', 1, 'J41', 10), STRUCT('Pulmonary', 1, 'J42', 10), STRUCT('Pulmonary', 1, 'J43', 10), STRUCT('Pulmonary', 1, 'J44', 10), STRUCT('Pulmonary', 1, 'J45', 10), STRUCT('Pulmonary', 1, 'J46', 10), STRUCT('Pulmonary', 1, 'J47', 10), STRUCT('Pulmonary', 1, 'J6', 10),
    STRUCT('Rheumatic', 1, '714', 9), STRUCT('Rheumatic', 1, 'M05', 10), STRUCT('Rheumatic', 1, 'M06', 10),
    STRUCT('PUD', 1, '531', 9), STRUCT('PUD', 1, '532', 9), STRUCT('PUD', 1, '533', 9), STRUCT('PUD', 1, '534', 9), STRUCT('PUD', 1, 'K25', 10), STRUCT('PUD', 1, 'K26', 10), STRUCT('PUD', 1, 'K27', 10), STRUCT('PUD', 1, 'K28', 10),
    STRUCT('MildLiver', 1, '571.2', 9), STRUCT('MildLiver', 1, '571.5', 9), STRUCT('MildLiver', 1, '571.6', 9), STRUCT('MildLiver', 1, 'K70.3', 10), STRUCT('MildLiver', 1, 'K74', 10),
    STRUCT('Diabetes', 1, '250.0', 9), STRUCT('Diabetes', 1, '250.1', 9), STRUCT('Diabetes', 1, '250.2', 9), STRUCT('Diabetes', 1, '250.3', 9), STRUCT('Diabetes', 1, 'E10.0', 10), STRUCT('Diabetes', 1, 'E10.1', 10), STRUCT('Diabetes', 1, 'E10.9', 10), STRUCT('Diabetes', 1, 'E11.0', 10), STRUCT('Diabetes', 1, 'E11.1', 10), STRUCT('Diabetes', 1, 'E11.9', 10),
    -- Weight 2
    STRUCT('DiabetesComp', 2, '250.4', 9), STRUCT('DiabetesComp', 2, '250.5', 9), STRUCT('DiabetesComp', 2, '250.6', 9), STRUCT('DiabetesComp', 2, '250.7', 9), STRUCT('DiabetesComp', 2, 'E10.2', 10), STRUCT('DiabetesComp', 2, 'E10.5', 10), STRUCT('DiabetesComp', 2, 'E11.2', 10), STRUCT('DiabetesComp', 2, 'E11.5', 10),
    STRUCT('Paraplegia', 2, '344.1', 9), STRUCT('Paraplegia', 2, '342', 9), STRUCT('Paraplegia', 2, 'G81', 10), STRUCT('Paraplegia', 2, 'G82', 10),
    STRUCT('Renal', 2, '582', 9), STRUCT('Renal', 2, '583', 9), STRUCT('Renal', 2, '585', 9), STRUCT('Renal', 2, '586', 9), STRUCT('Renal', 2, '588', 9), STRUCT('Renal', 2, 'N18', 10), STRUCT('Renal', 2, 'N19', 10),
    STRUCT('Cancer', 2, '14', 9), STRUCT('Cancer', 2, '15', 9), STRUCT('Cancer', 2, '16', 9), STRUCT('Cancer', 2, '17', 9), STRUCT('Cancer', 2, '18', 9), STRUCT('Cancer', 2, '190', 9), STRUCT('Cancer', 2, '191', 9), STRUCT('Cancer', 2, '192', 9), STRUCT('Cancer', 2, '193', 9), STRUCT('Cancer', 2, '194', 9), STRUCT('Cancer', 2, '195', 9), STRUCT('Cancer', 2, '20', 9), STRUCT('Cancer', 2, 'C0', 10), STRUCT('Cancer', 2, 'C1', 10), STRUCT('Cancer', 2, 'C2', 10), STRUCT('Cancer', 2, 'C3', 10), STRUCT('Cancer', 2, 'C4', 10), STRUCT('Cancer', 2, 'C5', 10), STRUCT('Cancer', 2, 'C6', 10), STRUCT('Cancer', 2, 'C70', 10), STRUCT('Cancer', 2, 'C71', 10), STRUCT('Cancer', 2, 'C72', 10), STRUCT('Cancer', 2, 'C81', 10), STRUCT('Cancer', 2, 'C82', 10), STRUCT('Cancer', 2, 'C83', 10), STRUCT('Cancer', 2, 'C84', 10), STRUCT('Cancer', 2, 'C85', 10), STRUCT('Cancer', 2, 'C9', 10),
    -- Weight 3
    STRUCT('SevereLiver', 3, '572.2', 9), STRUCT('SevereLiver', 3, '572.3', 9), STRUCT('SevereLiver', 3, '572.4', 9), STRUCT('SevereLiver', 3, 'K72', 10),
    -- Weight 6
    STRUCT('MetsCancer', 6, '196', 9), STRUCT('MetsCancer', 6, '197', 9), STRUCT('MetsCancer', 6, '198', 9), STRUCT('MetsCancer', 6, '199', 9), STRUCT('MetsCancer', 6, 'C77', 10), STRUCT('MetsCancer', 6, 'C78', 10), STRUCT('MetsCancer', 6, 'C79', 10), STRUCT('MetsCancer', 6, 'C80', 10),
    STRUCT('AIDS', 6, '042', 9), STRUCT('AIDS', 6, 'B20', 10)
  ])
),
charlson_scores AS (
  -- Calculates Charlson score for each admission, avoiding double counting
  SELECT
    dx.hadm_id,
    SUM(cw.weight) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  JOIN (
    -- Get the max weight for each condition group per admission
    SELECT DISTINCT
      dx.hadm_id,
      cw.condition,
      MAX(cw.weight) AS weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    JOIN charlson_weights AS cw
      ON dx.icd_version = cw.icd_version AND STARTS_WITH(dx.icd_code, cw.icd_prefix)
    GROUP BY dx.hadm_id, cw.condition
  ) AS cw ON dx.hadm_id = cw.hadm_id
  GROUP BY dx.hadm_id
),
cohort_with_outcomes AS (
  -- Defines the base cohort and calculates outcomes (LOS, mortality, AKI, ARDS)
  SELECT
    a.hadm_id,
    p.subject_id,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS admission_age,
    COALESCE(cs.charlson_score, 0) AS charlson_score,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    IF(p.dod IS NOT NULL AND DATE_DIFF(p.dod, a.admittime, DAY) BETWEEN 0 AND 90, 1, 0) AS mortality_90day_flag,
    IF(EXISTS(
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` aki_dx
      WHERE aki_dx.hadm_id = a.hadm_id
      AND ((aki_dx.icd_version = 9 AND aki_dx.icd_code LIKE '584%') OR (aki_dx.icd_version = 10 AND aki_dx.icd_code LIKE 'N17%'))
    ), 1, 0) AS has_aki,
    IF(EXISTS(
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` ards_dx
      WHERE ards_dx.hadm_id = a.hadm_id
      AND ((ards_dx.icd_version = 9 AND ards_dx.icd_code LIKE '518.82') OR (ards_dx.icd_version = 10 AND ards_dx.icd_code = 'J80'))
    ), 1, 0) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
  LEFT JOIN charlson_scores AS cs ON a.hadm_id = cs.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` pe_dx
      WHERE pe_dx.hadm_id = a.hadm_id
      AND ((pe_dx.icd_version = 9 AND pe_dx.icd_code LIKE '415.1%') OR (pe_dx.icd_version = 10 AND pe_dx.icd_code LIKE 'I26%'))
    )
)
SELECT
  -- Part 1: High comorbidity group stats
  (SELECT AVG(charlson_score) FROM cohort_with_outcomes WHERE charlson_score > p75_threshold) AS mean_risk_score_high_comorbidity,
  (SELECT AVG(mortality_90day_flag) FROM cohort_with_outcomes WHERE charlson_score > p75_threshold) AS mortality_90day_rate_high_comorbidity,

  -- Part 2: Comparison stats
  (SELECT AVG(los) FROM cohort_with_outcomes WHERE charlson_score > p75_threshold AND mortality_90day_flag = 0) AS los_survivors_high_comorbidity,
  (SELECT AVG(has_aki) FROM cohort_with_outcomes WHERE charlson_score > p75_threshold AND mortality_90day_flag = 0) AS aki_rate_survivors_high_comorbidity,
  (SELECT AVG(has_ards) FROM cohort_with_outcomes WHERE charlson_score > p75_threshold AND mortality_90day_flag = 0) AS ards_rate_survivors_high_comorbidity,

  (SELECT AVG(los) FROM cohort_with_outcomes) AS los_all_inpatients,
  (SELECT AVG(has_aki) FROM cohort_with_outcomes) AS aki_rate_all_inpatients,
  (SELECT AVG(has_ards) FROM cohort_with_outcomes) AS ards_rate_all_inpatients,

  -- Part 3: Matched profile percentile for 86-year-old
  (
    SELECT
      SAFE_DIVIDE(
        COUNTIF(c.charlson_score < avg_score_86yo),
        COUNT(c.charlson_score)
      )
    FROM cohort_with_outcomes AS c,
    (SELECT AVG(charlson_score) AS avg_score_86yo FROM cohort_with_outcomes WHERE admission_age = 86)
  ) AS matched_profile_risk_percentile_for_86yo

FROM (
  -- Calculate the 75th percentile threshold to define the high-comorbidity group
  SELECT APPROX_QUANTILES(charlson_score, 100)[OFFSET(75)] AS p75_threshold
  FROM cohort_with_outcomes
);