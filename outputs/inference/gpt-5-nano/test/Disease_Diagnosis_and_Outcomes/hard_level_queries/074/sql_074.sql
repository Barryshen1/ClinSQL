WITH
  -- Identify PE admissions
  pe_hadm AS (
    SELECT DISTINCT di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%pulmonary embolism%'
  ),

  -- Base cohort: male inpatients with PE
  cohort_base AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.dod AS dod,
      (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE a.hadm_id IN (SELECT hadm_id FROM pe_hadm)
      AND p.gender = 'M'
      AND 79 <= (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year))
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) <= 89
  ),

  -- Elixhauser-like comorbidity flags (subset)
  comorb_flags AS (
    SELECT
      di.hadm_id,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%congestive heart failure%' OR LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS CHF_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%arrhythmia%' OR LOWER(dd.long_title) LIKE '%atrial fibrillation%' THEN 1 ELSE 0 END) AS Arrhythmia_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%valvular%' THEN 1 ELSE 0 END) AS Valvular_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%pulmonary circulation disorders%' THEN 1 ELSE 0 END) AS PulmCirc_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%peripheral vascular disease%' THEN 1 ELSE 0 END) AS PVD_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%hypertension%' THEN 1 ELSE 0 END) AS HTN_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS Diabetes_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic pulmonary disease%' OR LOWER(dd.long_title) LIKE '%copd%' THEN 1 ELSE 0 END) AS COPD_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%renal%' OR LOWER(dd.long_title) LIKE '%nephropathy%' THEN 1 ELSE 0 END) AS Renal_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%liver%' THEN 1 ELSE 0 END) AS Liver_flag,
      MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cancer%' OR LOWER(dd.long_title) LIKE '%neoplasm%' THEN 1 ELSE 0 END) AS Cancer_flag
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    WHERE di.hadm_id IN (SELECT hadm_id FROM pe_hadm)
    GROUP BY di.hadm_id
  ),

  -- Combine comorbidity flags into a single burden score per admission
  cohort_with_comorb AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      c.admittime,
      c.dod,
      c.age_at_admit,
      (IFNULL(cf.CHF_flag,0)  + IFNULL(cf.Arrhythmia_flag,0) +
       IFNULL(cf.Valvular_flag,0) + IFNULL(cf.PulmCirc_flag,0) +
       IFNULL(cf.PVD_flag,0) + IFNULL(cf.HTN_flag,0) +
       IFNULL(cf.Diabetes_flag,0) + IFNULL(cf.COPD_flag,0) +
       IFNULL(cf.Renal_flag,0) + IFNULL(cf.Liver_flag,0) +
       IFNULL(cf.Cancer_flag,0)) AS comorbidity_burden
    FROM cohort_base AS c
    LEFT JOIN comorb_flags AS cf ON c.hadm_id = cf.hadm_id
  ),

  -- Determine 75th percentile of comorbidity_burden across the cohort
  p75_calc AS (
    SELECT (APPROX_QUANTILES(comorbidity_burden, 4)[OFFSET(3)]) AS p75
    FROM cohort_with_comorb
  ),

  -- Top-quartile admissions by comorbidity burden
  top_quart AS (
    SELECT cw.*, p75_calc.p75
    FROM cohort_with_comorb cw CROSS JOIN p75_calc
    WHERE cw.comorbidity_burden >= p75_calc.p75
  ),

  -- Per-admission percentile within the top quartile
  top_quart_with_percent AS (
    SELECT tq.hadm_id,
           tq.subject_id,
           tq.admittime,
           tq.dod,
           tq.age_at_admit,
           tq.comorbidity_burden,
           PERCENT_RANK() OVER (ORDER BY tq.comorbidity_burden) AS percentile_in_top
    FROM top_quart tq
  ),

  -- Cardiac complications within the admission
  cardio AS (
    SELECT hadm_id,
           MAX(CASE
                 WHEN LOWER(dd.long_title) LIKE '%myocardial%' OR LOWER(dd.long_title) LIKE '%infarction%' OR
                      LOWER(dd.long_title) LIKE '%cardiac arrest%' OR LOWER(dd.long_title) LIKE '%heart failure%' OR
                      LOWER(dd.long_title) LIKE '%atrial fibrillation%'
                 THEN 1 ELSE 0 END) AS has_cardio
    FROM top_quart tq
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON di.hadm_id = tq.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    GROUP BY hadm_id
  ),

  -- Neurologic complications within the admission
  neuro AS (
    SELECT hadm_id,
           MAX(CASE
                 WHEN LOWER(dd.long_title) LIKE '%stroke%' OR LOWER(dd.long_title) LIKE '%cerebrovascular%' OR
                      LOWER(dd.long_title) LIKE '%intracranial%' OR LOWER(dd.long_title) LIKE '%hemorrhage%'
                 THEN 1 ELSE 0 END) AS has_neuro
    FROM top_quart tq
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON di.hadm_id = tq.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    GROUP BY hadm_id
  ),

  -- 30-day mortality indicator
  death30 AS (
    SELECT tq.hadm_id,
           CASE
             WHEN p.dod IS NOT NULL AND DATE(p.dod) <= DATE(tq.admittime) + INTERVAL 30 DAY THEN 1
             ELSE 0
           END AS died_within_30
    FROM top_quart tq
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = tq.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  ),

  -- Survival days: days from admission to death; NULL if not died
  survival_days AS (
    SELECT tq.hadm_id,
           CASE
             WHEN p.dod IS NOT NULL THEN DATE(p.dod) - DATE(tq.admittime)
             ELSE NULL
           END AS survival_days
    FROM top_quart tq
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = tq.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  )
SELECT
  -- Target patient percentile within top quart
  (SELECT percentile_in_top
     FROM top_quart_with_percent
     WHERE hadm_id = @target_hadm_id) AS target_patient_percentile_in_top_quartile,

  -- Cohort-level metrics
  (SELECT COUNT(*) FROM top_quart) AS n_top_quartAdmissions,
  (SELECT AVG(CAST(died_within_30 AS FLOAT64)) FROM death30) AS mortality_30day_rate,
  (SELECT AVG(has_cardio) FROM cardio) AS cardiac_complication_rate,
  (SELECT AVG(has_neuro) FROM neuro) AS neuro_complication_rate,

  -- Median survival days among top-quart admissions
  (SELECT APPROX_QUANTILES(survival_days, 2)[OFFSET(1)]
     FROM survival_days
     WHERE survival_days IS NOT NULL) AS median_survival_days
FROM top_quart
LIMIT 1;