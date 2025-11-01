WITH dvt_patients AS (
  SELECT 
    adm.hadm_id,
    pat.subject_id,
    -- Calculate age at admission using MIMIC-IV methodology
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_adm,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    -- DVT ICD-10 codes (I80.2-I80.9, I82.0-I82.9)
    (diag.icd_code LIKE 'I802%' OR diag.icd_code LIKE 'I803%' OR 
     diag.icd_code LIKE 'I808%' OR diag.icd_code LIKE 'I809%' OR
     diag.icd_code LIKE 'I820%' OR diag.icd_code LIKE 'I821%' OR
     diag.icd_code LIKE 'I822%' OR diag.icd_code LIKE 'I823%' OR
     diag.icd_code LIKE 'I824%' OR diag.icd_code LIKE 'I828%' OR
     diag.icd_code LIKE 'I829%')
    AND pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 59 AND 69
  GROUP BY adm.hadm_id, pat.subject_id, pat.anchor_age, pat.anchor_year, pat.gender, adm.admittime
),

comorbidity_scores AS (
  SELECT 
    dp.hadm_id,
    dp.subject_id,
    COUNT(DISTINCT elix.condition) AS elixhauser_score
  FROM dvt_patients dp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON dp.hadm_id = diag.hadm_id
  -- Simplified Elixhauser mapping (in practice, use full mapping)
  LEFT JOIN UNNEST([
    STRUCT('I10' AS icd_prefix, 'HYPERTENSION' AS condition),
    STRUCT('E11' AS icd_prefix, 'DIABETES' AS condition),
    STRUCT('I25' AS icd_prefix, 'CARDIAC' AS condition),
    STRUCT('I63' AS icd_prefix, 'STROKE' AS condition),
    STRUCT('I80' AS icd_prefix, 'VENOUS' AS condition),
    STRUCT('I82' AS icd_prefix, 'EMBOLISM' AS condition),
    STRUCT('C' AS icd_prefix, 'CANCER' AS condition),
    STRUCT('J44' AS icd_prefix, 'COPD' AS condition)
  ]) elix
    ON STARTS_WITH(diag.icd_code, elix.icd_prefix)
  GROUP BY dp.hadm_id, dp.subject_id
),

cohort_threshold AS (
  SELECT 
    APPROX_QUANTILES(elixhauser_score, 100)[OFFSET(75)] AS p75_score
  FROM comorbidity_scores
),

high_comorbidity_cohort AS (
  SELECT 
    cs.hadm_id,
    cs.subject_id,
    cs.elixhauser_score,
    adm.admittime,
    adm.deathtime,
    pat.dod
  FROM comorbidity_scores cs
  CROSS JOIN cohort_threshold ct
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON cs.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON cs.subject_id = pat.subject_id
  WHERE cs.elixhauser_score >= ct.p75_score
),

mortality_data AS (
  SELECT 
    h.hadm_id,
    -- Calculate 30-day mortality
    CASE 
      WHEN h.deathtime IS NOT NULL AND h.deathtime <= DATETIME_ADD(h.admittime, INTERVAL 30 DAY) THEN 1
      WHEN h.deathtime IS NULL AND h.dod IS NOT NULL AND h.dod <= DATETIME_ADD(h.admittime, INTERVAL 30 DAY) THEN 1
      ELSE 0 
    END AS mortality_30d,
    -- Calculate survival time for decedents (in days)
    CASE 
      WHEN (h.deathtime IS NOT NULL AND h.deathtime <= DATETIME_ADD(h.admittime, INTERVAL 30 DAY))
        THEN DATETIME_DIFF(h.deathtime, h.admittime, DAY)
      WHEN (h.dod IS NOT NULL AND h.dod <= DATETIME_ADD(h.admittime, INTERVAL 30 DAY))
        THEN DATE_DIFF(h.dod, CAST(h.admittime AS DATE), DAY)
      ELSE NULL 
    END AS survival_days,
    -- Major complication: Pulmonary Embolism (PE) diagnosis
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE diag.hadm_id = h.hadm_id 
        AND (diag.icd_code LIKE 'I26%' OR diag.icd_code LIKE 'I260%')
    ) AS has_pe,
    h.elixhauser_score  -- Critical addition for quartile calculations
  FROM high_comorbidity_cohort h
)

SELECT 
  COUNT(*) AS cohort_size,
  AVG(CAST(mortality_30d AS FLOAT64)) AS mortality_30d_rate,
  AVG(CAST(has_pe AS FLOAT64)) AS complication_rate,
  APPROX_QUANTILES(survival_days, 100 IGNORE NULLS)[OFFSET(50)] AS median_survival_decedents_days,
  APPROX_QUANTILES(elixhauser_score, 4)[OFFSET(1)] AS q1_composite_score,
  APPROX_QUANTILES(elixhauser_score, 4)[OFFSET(2)] AS q2_composite_score,
  APPROX_QUANTILES(elixhauser_score, 4)[OFFSET(3)] AS q3_composite_score
FROM mortality_data;