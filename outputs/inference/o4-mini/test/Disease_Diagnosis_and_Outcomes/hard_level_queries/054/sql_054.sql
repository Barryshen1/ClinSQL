WITH
-- Step 1: Base female patients age 59-69
base_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING (subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- Step 2: Identify PE admissions
pe_flags AS (
  SELECT DISTINCT
    subject_id,
    hadm_id,
    1 AS has_pe
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND STARTS_WITH(icd_code, 'I26')
),

-- Step 3: Compute comorbidity score (count distinct non-PE ICD codes per admission)
comorbidity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code)
    - SUM(CASE WHEN icd_version = 10 AND STARTS_WITH(icd_code, 'I26') THEN 1 ELSE 0 END)
      AS comorbidity_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
  GROUP BY subject_id, hadm_id
),

-- Step 4: Identify cardio and neuro complications
complications AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN icd_version = 10 
                 AND (icd_code BETWEEN 'I21' AND 'I22') THEN 1 ELSE 0 END) AS cardio_comp,
    MAX(CASE WHEN icd_version = 10
                 AND (STARTS_WITH(icd_code, 'I61')
                      OR STARTS_WITH(icd_code, 'G40')
                      OR STARTS_WITH(icd_code, 'G41'))
             THEN 1 ELSE 0 END) AS neuro_comp
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),

-- Step 5: Combine all metrics for each admission
admission_metrics AS (
  SELECT
    bp.subject_id,
    bp.hadm_id,
    bp.admittime,
    bp.dischtime,
    bp.deathtime,
    bp.dod,
    COALESCE(pf.has_pe, 0)          AS has_pe,
    COALESCE(cm.comorbidity_score, 0) AS comorbidity_score,
    COALESCE(comp.cardio_comp, 0)    AS cardio_complication,
    COALESCE(comp.neuro_comp, 0)     AS neuro_complication,
    DATE_DIFF(CAST(bp.dischtime AS DATE), CAST(bp.admittime AS DATE), DAY) AS los_days,
    CASE
      WHEN bp.deathtime IS NOT NULL
           AND DATE_DIFF(CAST(bp.deathtime AS DATE), CAST(bp.admittime AS DATE), DAY) <= 30 THEN 1
      WHEN bp.dod IS NOT NULL
           AND DATE_DIFF(CAST(bp.dod AS DATE), CAST(bp.admittime AS DATE), DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30d
  FROM base_patients bp
  LEFT JOIN pe_flags pf USING (subject_id, hadm_id)
  LEFT JOIN comorbidity cm USING (subject_id, hadm_id)
  LEFT JOIN complications comp USING (subject_id, hadm_id)
),

-- Step 6: Separate PE vs control cohorts
pe_cohort AS (
  SELECT * FROM admission_metrics WHERE has_pe = 1
),
control_cohort AS (
  SELECT * FROM admission_metrics WHERE has_pe = 0
),

-- Step 7: Summarize cohort‐level metrics (now with matched_percentile placeholder)
summary AS (
  SELECT
    'PE Cohort' AS cohort,
    COUNT(*)                                    AS n_admissions,
    AVG(comorbidity_score)                      AS mean_comorbidity_score,
    AVG(died_within_30d)                        AS mortality_30d_rate,
    AVG(cardio_complication)                    AS cardio_complication_rate,
    AVG(neuro_complication)                     AS neuro_complication_rate,
    AVG(CASE WHEN died_within_30d = 0 THEN los_days END) AS mean_los_survivors,
    NULL                                         AS matched_percentile
  FROM pe_cohort
  UNION ALL
  SELECT
    'Control Cohort' AS cohort,
    COUNT(*)                                    AS n_admissions,
    AVG(comorbidity_score)                      AS mean_comorbidity_score,
    AVG(died_within_30d)                        AS mortality_30d_rate,
    AVG(cardio_complication)                    AS cardio_complication_rate,
    AVG(neuro_complication)                     AS neuro_complication_rate,
    AVG(CASE WHEN died_within_30d = 0 THEN los_days END) AS mean_los_survivors,
    NULL                                         AS matched_percentile
  FROM control_cohort
),

-- Step 8: Compute percentile rank of PE patients vs controls by comorbidity
control_scores AS (
  SELECT comorbidity_score
  FROM control_cohort
),
pe_percentiles AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.comorbidity_score,
    PERCENT_RANK() OVER (ORDER BY p.comorbidity_score) AS percentile_within_pe,
    (
      SELECT COUNTIF(cs.comorbidity_score <= p.comorbidity_score) 
             / COUNT(*) 
      FROM control_scores cs
    ) AS pctile_vs_controls
  FROM pe_cohort p
)

-- Final output: now both branches have 8 columns
SELECT * FROM summary
UNION ALL
SELECT
  CONCAT('PE patient ', subject_id, '/', hadm_id) AS cohort,
  NULL                        AS n_admissions,
  comorbidity_score           AS mean_comorbidity_score,
  NULL                        AS mortality_30d_rate,
  NULL                        AS cardio_complication_rate,
  NULL                        AS neuro_complication_rate,
  NULL                        AS mean_los_survivors,
  pctile_vs_controls          AS matched_percentile
FROM pe_percentiles
ORDER BY cohort;