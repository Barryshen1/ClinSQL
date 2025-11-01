WITH
-- optional parameter: set target_hadm_id to a specific hadm_id (uncomment/replace),
-- or leave NULL to auto-select a matching 76-year-old male admission with DVT and high comorbidity.
params AS (
  -- Replace the value below with a specific hadm_id if you have one, e.g. SELECT 123456 AS target_hadm_id
  -- Or leave NULL to auto-pick a matching admission
  SELECT NULL AS target_hadm_id
),

-- base admission + patient info with computed age at admission
base_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    p.gender,
    -- approximate age at admission using anchor_age + year offset (common MIMIC approach)
    SAFE_CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT64) AS age_at_adm
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
),

-- Identify admissions with DVT via diagnosis text matching
dvt_flags AS (
  SELECT DISTINCT
    d.hadm_id,
    1 AS has_dvt
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      USING (icd_code, icd_version)
  WHERE
    LOWER(COALESCE(ddi.long_title, '')) LIKE '%deep vein%'
    OR LOWER(COALESCE(ddi.long_title, '')) LIKE '%venous thrombosis%'
    OR LOWER(COALESCE(ddi.long_title, '')) LIKE '%thrombophlebitis%'
    OR LOWER(COALESCE(ddi.long_title, '')) LIKE '%phlebitis and thrombosis%'
),

-- Derive comorbidity flags per admission by scanning diagnoses long_title
comorb_flags AS (
  SELECT
    d.hadm_id,
    -- comorbidity group flags (1/0)
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%congestive heart failure%' OR LOWER(ddi.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_chf,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%chronic obstructive%' OR LOWER(ddi.long_title) LIKE '%chronic bronchitis%' OR LOWER(ddi.long_title) LIKE '%emphysema%' OR LOWER(ddi.long_title) LIKE '%pulmonary disease%' THEN 1 ELSE 0 END) AS has_copd,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%dementia%' THEN 1 ELSE 0 END) AS has_dementia,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%diabetes with%' OR LOWER(ddi.long_title) LIKE '%diabetes complications%' THEN 1 ELSE 0 END) AS has_diab_comp,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%diabetes%' AND NOT (LOWER(ddi.long_title) LIKE '%diabetes with%' OR LOWER(ddi.long_title) LIKE '%diabetes complications%') THEN 1 ELSE 0 END) AS has_diab,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%renal failure%' OR LOWER(ddi.long_title) LIKE '%chronic kidney%' OR LOWER(ddi.long_title) LIKE '%kidney failure%' THEN 1 ELSE 0 END) AS has_renal,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%liver%' AND NOT LOWER(ddi.long_title) LIKE '%malignant%' THEN 1 ELSE 0 END) AS has_liver,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%malignan%' OR LOWER(ddi.long_title) LIKE '%neoplasm%' OR LOWER(ddi.long_title) LIKE '%cancer%' THEN 1 ELSE 0 END) AS has_malignancy,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%metastatic%' THEN 1 ELSE 0 END) AS has_metastatic,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%cerebrovascular%' OR LOWER(ddi.long_title) LIKE '%stroke%' OR LOWER(ddi.long_title) LIKE '%cva%' THEN 1 ELSE 0 END) AS has_cva,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%peripheral vascular%' OR LOWER(ddi.long_title) LIKE '%peripheral artery%' OR LOWER(ddi.long_title) LIKE '%atheroscleros%' THEN 1 ELSE 0 END) AS has_pvd,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%hiv%' OR LOWER(ddi.long_title) LIKE '%aids%' THEN 1 ELSE 0 END) AS has_hiv
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      USING (icd_code, icd_version)
  GROUP BY d.hadm_id
),

-- Complication flags (acute events during the admission)
complication_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%pulmonary embolism%' OR LOWER(ddi.long_title) LIKE '%embolism of pulmonary%' OR LOWER(ddi.long_title) LIKE '%pulmonary embolus%' THEN 1 ELSE 0 END) AS has_pe,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%myocardial infarction%' OR LOWER(ddi.long_title) LIKE '%acute myocardial%' OR LOWER(ddi.long_title) LIKE '%acute mi%' THEN 1 ELSE 0 END) AS has_mi,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%cerebrovascular%' OR LOWER(ddi.long_title) LIKE '%stroke%' OR LOWER(ddi.long_title) LIKE '%cva%' THEN 1 ELSE 0 END) AS has_stroke,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%sepsis%' OR LOWER(ddi.long_title) LIKE '%septicemia%' THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%hemorrhage%' OR LOWER(ddi.long_title) LIKE '%haemorrhage%' OR LOWER(ddi.long_title) LIKE '%bleeding%' OR LOWER(ddi.long_title) LIKE '%gastrointestinal hemorrhage%' THEN 1 ELSE 0 END) AS has_bleed,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%acute renal failure%' OR LOWER(ddi.long_title) LIKE '%acute kidney%' OR LOWER(ddi.long_title) LIKE '%acute renal%' THEN 1 ELSE 0 END) AS has_arf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      USING (icd_code, icd_version)
  GROUP BY d.hadm_id
),

-- Combine flags and compute a simple comorbidity_count (number of comorbidity groups present)
adm_with_scores AS (
  SELECT
    b.hadm_id,
    b.subject_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    b.dod,
    b.gender,
    b.age_at_adm,
    COALESCE(dvt.has_dvt, 0) AS has_dvt,
    COALESCE(cf.has_chf, 0) AS has_chf,
    COALESCE(cf.has_copd, 0) AS has_copd,
    COALESCE(cf.has_dementia, 0) AS has_dementia,
    COALESCE(cf.has_diab, 0) AS has_diab,
    COALESCE(cf.has_diab_comp, 0) AS has_diab_comp,
    COALESCE(cf.has_renal, 0) AS has_renal,
    COALESCE(cf.has_liver, 0) AS has_liver,
    COALESCE(cf.has_malignancy, 0) AS has_malignancy,
    COALESCE(cf.has_metastatic, 0) AS has_metastatic,
    COALESCE(cf.has_cva, 0) AS has_cva,
    COALESCE(cf.has_pvd, 0) AS has_pvd,
    COALESCE(cf.has_hiv, 0) AS has_hiv,
    COALESCE(comp.has_pe, 0) AS has_pe,
    COALESCE(comp.has_mi, 0) AS has_mi,
    COALESCE(comp.has_stroke, 0) AS has_stroke,
    COALESCE(comp.has_sepsis, 0) AS has_sepsis,
    COALESCE(comp.has_bleed, 0) AS has_bleed,
    COALESCE(comp.has_arf, 0) AS has_arf,
    -- simple comorbidity count: number of chronic comorbidity groups present
    (COALESCE(cf.has_chf,0)
     + COALESCE(cf.has_copd,0)
     + COALESCE(cf.has_dementia,0)
     + COALESCE(cf.has_diab,0)
     + COALESCE(cf.has_diab_comp,0)
     + COALESCE(cf.has_renal,0)
     + COALESCE(cf.has_liver,0)
     + COALESCE(cf.has_malignancy,0)
     + COALESCE(cf.has_metastatic,0)
     + COALESCE(cf.has_cva,0)
     + COALESCE(cf.has_pvd,0)
     + COALESCE(cf.has_hiv,0)
    ) AS comorbidity_count
  FROM
    base_adm b
    LEFT JOIN dvt_flags dvt USING (hadm_id)
    LEFT JOIN comorb_flags cf USING (hadm_id)
    LEFT JOIN complication_flags comp USING (hadm_id)
),

-- Define the target cohorts:
-- Cohort A: male inpatients aged 71-81 with DVT and high comorbidity (comorbidity_count >= 3)
dvt_high_comorb AS (
  SELECT *
  FROM adm_with_scores
  WHERE gender = 'M'
    AND age_at_adm BETWEEN 71 AND 81
    AND has_dvt = 1
    AND comorbidity_count >= 3
),

-- Comparison cohort: general male inpatients aged 71-81 (no DVT/comorb requirement)
general_male_71_81 AS (
  SELECT *
  FROM adm_with_scores
  WHERE gender = 'M'
    AND age_at_adm BETWEEN 71 AND 81
),

-- Aggregates for cohort A (DVT + high comorbidity)
dvt_metrics AS (
  SELECT
    COUNT(*) AS n_admissions,
    -- risk score distribution (Q1, median, Q3) using APPROX_QUANTILES with direct indexing
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(25)] AS q1_comorbidity,
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(50)] AS median_comorbidity,
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS q3_comorbidity,
    -- 90-day mortality
    SUM(CASE WHEN dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90 THEN 1 ELSE 0 END) AS deaths_90d,
    SUM(CASE WHEN (dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90) THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS mortality_90d_rate,
    -- major complication rate (any of has_pe, has_mi, has_stroke, has_sepsis, has_bleed, has_arf)
    SUM(CASE WHEN (has_pe + has_mi + has_stroke + has_sepsis + has_bleed + has_arf) > 0 THEN 1 ELSE 0 END) AS n_major_comp,
    SUM(CASE WHEN (has_pe + has_mi + has_stroke + has_sepsis + has_bleed + has_arf) > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS major_comp_rate,
    -- survivor LOS median (days) among hospital survivors
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(dischtime, admittime, DAY) ELSE NULL END, 100)[OFFSET(50)] AS median_survivor_los_days,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(dischtime, admittime, DAY) ELSE NULL END, 100)[OFFSET(25)] AS q1_survivor_los_days,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(dischtime, admittime, DAY) ELSE NULL END, 100)[OFFSET(75)] AS q3_survivor_los_days
  FROM dvt_high_comorb
),

-- Aggregates for comparison cohort (general male 71-81)
general_metrics AS (
  SELECT
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN (has_pe + has_mi + has_stroke + has_sepsis + has_bleed + has_arf) > 0 THEN 1 ELSE 0 END) AS n_major_comp,
    SUM(CASE WHEN (has_pe + has_mi + has_stroke + has_sepsis + has_bleed + has_arf) > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS major_comp_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(dischtime, admittime, DAY) ELSE NULL END, 100)[OFFSET(50)] AS median_survivor_los_days,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(dischtime, admittime, DAY) ELSE NULL END, 100)[OFFSET(25)] AS q1_survivor_los_days,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(dischtime, admittime, DAY) ELSE NULL END, 100)[OFFSET(75)] AS q3_survivor_los_days
  FROM general_male_71_81
),

-- Compute target patient's comorbidity_count and percentile within the DVT cohort
patient_score AS (
  SELECT
    t.hadm_id,
    t.comorbidity_count AS patient_comorbidity_count
  FROM
    adm_with_scores t,
    params p
  WHERE
    -- If params.target_hadm_id is provided (not NULL) use that admission; otherwise attempt to auto-select
    -- a 76-year-old male with DVT and high comorbidity (comorbidity_count >= 3).
    (p.target_hadm_id IS NOT NULL AND t.hadm_id = p.target_hadm_id)
    OR (
      p.target_hadm_id IS NULL
      AND t.gender = 'M'
      AND t.age_at_adm = 76
      AND t.has_dvt = 1
      AND t.comorbidity_count >= 3
    )
  LIMIT 1
),

patient_percentile AS (
  SELECT
    p.hadm_id,
    p.patient_comorbidity_count,
    COUNT(*) OVER() AS cohort_n,
    SUM(CASE WHEN d.comorbidity_count < p.patient_comorbidity_count THEN 1 ELSE 0 END) OVER() AS n_less,
    SUM(CASE WHEN d.comorbidity_count <= p.patient_comorbidity_count THEN 1 ELSE 0 END) OVER() AS n_leq,
    ROUND(100.0 * SUM(CASE WHEN d.comorbidity_count < p.patient_comorbidity_count THEN 1 ELSE 0 END) OVER() / NULLIF(COUNT(*) OVER(),0),2) AS percentile_strict_less,
    ROUND(100.0 * SUM(CASE WHEN d.comorbidity_count <= p.patient_comorbidity_count THEN 1 ELSE 0 END) OVER() / NULLIF(COUNT(*) OVER(),0),2) AS percentile_inclusive
  FROM
    patient_score p
    -- compare to all admissions in the DVT cohort (male, 71-81 with DVT), i.e., dvt_high_comorb
    JOIN dvt_high_comorb d ON TRUE
  LIMIT 1
)

-- Final output: cohort metrics and patient percentile
SELECT
  -- DVT + high comorbidity cohort metrics
  dm.n_admissions AS dvt_high_n,
  dm.q1_comorbidity AS dvt_high_q1_comorbidity,
  dm.median_comorbidity AS dvt_high_median_comorbidity,
  dm.q3_comorbidity AS dvt_high_q3_comorbidity,
  dm.deaths_90d AS dvt_high_deaths_90d,
  ROUND(dm.mortality_90d_rate * 100, 2) AS dvt_high_mortality_90d_pct,
  dm.n_major_comp AS dvt_high_n_major_complications,
  ROUND(dm.major_comp_rate * 100, 2) AS dvt_high_major_comp_rate_pct,
  dm.median_survivor_los_days AS dvt_high_median_survivor_los_days,
  dm.q1_survivor_los_days AS dvt_high_survivor_los_q1_days,
  dm.q3_survivor_los_days AS dvt_high_survivor_los_q3_days,

  -- General comparator metrics (male 71-81)
  gm.n_admissions AS general_n,
  gm.n_major_comp AS general_n_major_complications,
  ROUND(gm.major_comp_rate * 100, 2) AS general_major_comp_rate_pct,
  gm.median_survivor_los_days AS general_median_survivor_los_days,
  gm.q1_survivor_los_days AS general_survivor_los_q1_days,
  gm.q3_survivor_los_days AS general_survivor_los_q3_days,

  -- Patient-specific score and percentile
  ps.hadm_id AS target_hadm_id,
  ps.patient_comorbidity_count AS target_comorbidity_count,
  COALESCE(pp.cohort_n, 0) AS dvt_cohort_size_for_percentile,
  COALESCE(pp.n_less, 0) AS n_with_lower_score,
  COALESCE(pp.n_leq, 0) AS n_with_lower_or_equal_score,
  COALESCE(pp.percentile_strict_less, 0) AS percentile_strictly_lower_pct,
  COALESCE(pp.percentile_inclusive, 0) AS percentile_inclusive_pct

FROM dvt_metrics dm
CROSS JOIN general_metrics gm
LEFT JOIN patient_score ps ON TRUE
LEFT JOIN patient_percentile pp ON TRUE;