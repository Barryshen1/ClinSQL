WITH
-- Define pulmonary embolism ICD codes (ICD-9 and ICD-10)
pe_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%pulmonary embolism%'
     OR LOWER(long_title) LIKE '%pulmonary thromboembolism%'
     OR icd_code IN ('415.19', 'I26.99') -- Common PE codes
),

-- Get male inpatients aged 79-89 with PE
pe_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.dod,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN pe_icd_codes pe ON d.icd_code = pe.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admission_type != 'NEWBORN' -- Exclude newborn admissions
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, p.anchor_age, p.dod
),

-- Calculate quartiles for comorbidity burden
comorbidity_quartiles AS (
  SELECT
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS top_quartile
  FROM pe_patients
),

-- Filter patients in top quartile of comorbidity burden
top_quartile_pe_patients AS (
  SELECT
    p.*,
    c.top_quartile
  FROM pe_patients p
  CROSS JOIN comorbidity_quartiles c
  WHERE p.comorbidity_count >= c.top_quartile
),

-- Calculate composite risk score (simplified example)
risk_scores AS (
  SELECT
    subject_id,
    hadm_id,
    -- Simple composite score: age + (comorbidity_count * 2)
    (anchor_age + (comorbidity_count * 2)) AS composite_score,
    PERCENT_RANK() OVER(ORDER BY (anchor_age + (comorbidity_count * 2))) AS percentile_rank
  FROM top_quartile_pe_patients
),

-- Get cardiac and neurologic complications
complications AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    MAX(CASE WHEN d.long_title LIKE '%cardiac%' THEN 1 ELSE 0 END) AS has_cardiac_complication,
    MAX(CASE WHEN d.long_title LIKE '%neurologic%' OR d.long_title LIKE '%neurological%' THEN 1 ELSE 0 END) AS has_neurologic_complication
  FROM risk_scores r
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON r.subject_id = diag.subject_id AND r.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  GROUP BY r.subject_id, r.hadm_id
),

-- Calculate 30-day mortality
mortality AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    CASE
      WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
      WHEN p.dod IS NOT NULL AND TIMESTAMP_DIFF(p.dod, a.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30_days,
    CASE
      WHEN a.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY)
      WHEN p.dod IS NOT NULL THEN TIMESTAMP_DIFF(p.dod, a.admittime, DAY)
      ELSE NULL
    END AS survival_days
  FROM risk_scores r
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON r.subject_id = a.subject_id AND r.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON r.subject_id = p.subject_id
),

-- Final results
final_results AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.composite_score,
    r.percentile_rank,
    m.died_within_30_days,
    c.has_cardiac_complication,
    c.has_neurologic_complication,
    m.survival_days
  FROM risk_scores r
  JOIN mortality m ON r.subject_id = m.subject_id AND r.hadm_id = m.hadm_id
  JOIN complications c ON r.subject_id = c.subject_id AND r.hadm_id = c.hadm_id
)

-- Aggregate results
SELECT
  -- For the specific patient (you would filter for their subject_id/hadm_id)
  -- Here we show aggregate statistics for the cohort
  COUNT(*) AS total_patients,
  AVG(percentile_rank) AS avg_percentile_rank,
  AVG(died_within_30_days) AS thirty_day_mortality_rate,
  AVG(has_cardiac_complication) AS cardiac_complication_rate,
  AVG(has_neurologic_complication) AS neurologic_complication_rate,
  PERCENTILE_CONT(survival_days, 0.5) OVER() AS median_survival_days
FROM final_results;