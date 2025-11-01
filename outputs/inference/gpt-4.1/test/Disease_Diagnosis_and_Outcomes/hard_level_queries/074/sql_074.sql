WITH pe_codes AS (
  -- ICD codes for pulmonary embolism
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '4151%')
     OR (icd_version = 10 AND icd_code LIKE 'I26%')
),
cardiac_codes AS (
  -- ICD codes for cardiac complications
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '428%' OR icd_code LIKE '427%'))
     OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I50%' OR icd_code LIKE 'I47%' OR icd_code LIKE 'I48%' OR icd_code LIKE 'I49%'))
),
neuro_codes AS (
  -- ICD codes for neurologic complications
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND (icd_code LIKE '434%' OR icd_code LIKE '436%' OR icd_code LIKE '435%' OR icd_code LIKE '7803%'))
     OR (icd_version = 10 AND (icd_code LIKE 'I63%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'G45%' OR icd_code LIKE 'G40%'))
),
pe_admissions AS (
  -- Admissions for male patients aged 79-89 with PE
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN pe_codes
    ON diag.icd_code = pe_codes.icd_code AND diag.icd_version = pe_codes.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 79 AND 89
),
comorbidity_counts AS (
  -- Count unique diagnoses per admission
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort AS (
  -- Cohort: male, 79-89, PE, with comorbidity count
  SELECT
    pe.*,
    c.comorbidity_count
  FROM pe_admissions pe
  LEFT JOIN comorbidity_counts c
    ON pe.hadm_id = c.hadm_id
),
quartile_threshold AS (
  -- 75th percentile of comorbidity count in cohort
  SELECT
    APPROX_QUANTILES(comorbidity_count, 4)[OFFSET(3)] AS comorbidity_q3
  FROM cohort
),
top_quartile_cohort AS (
  -- Cohort admissions in top quartile of comorbidity burden
  SELECT
    c.*,
    CASE WHEN c.anchor_age = 84 THEN 1 ELSE 0 END AS is_index_patient
  FROM cohort c
  CROSS JOIN quartile_threshold q
  WHERE c.comorbidity_count >= q.comorbidity_q3
),
cardiac_complications AS (
  -- Admissions with cardiac complications
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN cardiac_codes
    ON diag.icd_code = cardiac_codes.icd_code AND diag.icd_version = cardiac_codes.icd_version
),
neuro_complications AS (
  -- Admissions with neurologic complications
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN neuro_codes
    ON diag.icd_code = neuro_codes.icd_code AND diag.icd_version = neuro_codes.icd_version
),
outcomes AS (
  -- Calculate outcomes for top quartile cohort
  SELECT
    t.hadm_id,
    t.subject_id,
    t.anchor_age,
    t.comorbidity_count,
    t.is_index_patient,
    t.admittime,
    t.deathtime,
    t.hospital_expire_flag,
    -- 30-day mortality: death within 30 days of admission
    CASE
      WHEN t.deathtime IS NOT NULL AND DATETIME_DIFF(t.deathtime, t.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    -- Cardiac complication
    CASE WHEN cc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS cardiac_complication,
    -- Neurologic complication
    CASE WHEN nc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS neuro_complication,
    -- Survival days: death or censored at discharge
    CASE
      WHEN t.deathtime IS NOT NULL THEN DATETIME_DIFF(t.deathtime, t.admittime, DAY)
      ELSE DATETIME_DIFF(t.dischtime, t.admittime, DAY)
    END AS survival_days
  FROM top_quartile_cohort t
  LEFT JOIN cardiac_complications cc ON t.hadm_id = cc.hadm_id
  LEFT JOIN neuro_complications nc ON t.hadm_id = nc.hadm_id
),
percentile_calc AS (
  -- Calculate percentile for index patient
  SELECT
    o.hadm_id,
    o.subject_id,
    o.comorbidity_count,
    o.is_index_patient,
    -- Percentile: proportion of cohort with comorbidity count <= index patient
    (SELECT
      ROUND(100.0 * COUNTIF(comorbidity_count <= o.comorbidity_count) / COUNT(*), 1)
     FROM outcomes
     WHERE is_index_patient = 0 OR o.is_index_patient = 1
    ) AS composite_risk_score_percentile
  FROM outcomes o
  WHERE o.is_index_patient = 1
),
summary AS (
  -- Aggregate cohort outcomes
  SELECT
    COUNT(*) AS cohort_size,
    ROUND(100.0 * AVG(mortality_30d), 1) AS mortality_30d_rate,
    ROUND(100.0 * AVG(cardiac_complication), 1) AS cardiac_complication_rate,
    ROUND(100.0 * AVG(neuro_complication), 1) AS neuro_complication_rate,
    APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days
  FROM outcomes
)
SELECT
  p.composite_risk_score_percentile,
  s.mortality_30d_rate,
  s.cardiac_complication_rate,
  s.neuro_complication_rate,
  s.median_survival_days
FROM percentile_calc p
CROSS JOIN summary s;