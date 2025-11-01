WITH
-- List of admissions that had any ICU stay (deduplicated per admission)
icu_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Aggregate ICD diagnosis text per admission and compute flags for Charlson components and complications
diag_flags AS (
  SELECT
    d.hadm_id,
    -- Charlson component flags (keyword-based, approximate)
    MAX(IF(LOWER(diag.long_title) LIKE '%myocardial infarction%' OR LOWER(diag.long_title) LIKE '%acute mi%' , 1, 0)) AS charlson_mi,
    MAX(IF(LOWER(diag.long_title) LIKE '%congestive heart failure%' OR LOWER(diag.long_title) LIKE '%heart failure%' , 1, 0)) AS charlson_chf,
    MAX(IF(LOWER(diag.long_title) LIKE '%peripheral vascular%' OR LOWER(diag.long_title) LIKE '%peripheral vascular disease%' OR LOWER(diag.long_title) LIKE '%pvd%', 1, 0)) AS charlson_pvd,
    MAX(IF(LOWER(diag.long_title) LIKE '%cerebrovascular%' OR LOWER(diag.long_title) LIKE '%stroke%' OR LOWER(diag.long_title) LIKE '%transient ischemic attack%' OR LOWER(diag.long_title) LIKE '%tia%', 1, 0)) AS charlson_cvd,
    MAX(IF(LOWER(diag.long_title) LIKE '%dementia%' , 1, 0)) AS charlson_dementia,
    MAX(IF(LOWER(diag.long_title) LIKE '%chronic obstructive%' OR LOWER(diag.long_title) LIKE '%emphysema%' OR LOWER(diag.long_title) LIKE '%copd%', 1, 0)) AS charlson_copd,
    MAX(IF(LOWER(diag.long_title) LIKE '%rheumatic%' , 1, 0)) AS charlson_rheumatic,
    MAX(IF(LOWER(diag.long_title) LIKE '%peptic ulcer%' OR LOWER(diag.long_title) LIKE '%peptic ulcer disease%' OR LOWER(diag.long_title) LIKE '%gastric ulcer%', 1, 0)) AS charlson_pud,
    -- liver disease (split mild vs moderate/severe)
    MAX(IF(LOWER(diag.long_title) LIKE '%cirrhosis%' OR LOWER(diag.long_title) LIKE '%hepatic failure%' OR LOWER(diag.long_title) LIKE '%portal hypertension%', 1, 0)) AS charlson_liver_modsev,
    MAX(IF(LOWER(diag.long_title) LIKE '%chronic hepatitis%' OR LOWER(diag.long_title) LIKE '%mild liver%' OR LOWER(diag.long_title) LIKE '%fatty liver%', 1, 0)) AS charlson_liver_mild,
    -- Diabetes
    MAX(IF(LOWER(diag.long_title) LIKE '%diabetes%' AND (LOWER(diag.long_title) LIKE '%with%' OR LOWER(diag.long_title) LIKE '%complication%' OR LOWER(diag.long_title) LIKE '%neuropathy%' OR LOWER(diag.long_title) LIKE '%retinopathy%' OR LOWER(diag.long_title) LIKE '%nephropathy%'), 1, 0)) AS charlson_dm_with_comp,
    MAX(IF(LOWER(diag.long_title) LIKE '%diabetes%' AND NOT (LOWER(diag.long_title) LIKE '%with%' OR LOWER(diag.long_title) LIKE '%complication%' OR LOWER(diag.long_title) LIKE '%neuropathy%' OR LOWER(diag.long_title) LIKE '%retinopathy%' OR LOWER(diag.long_title) LIKE '%nephropathy%'), 1, 0)) AS charlson_dm_no_comp,
    MAX(IF(LOWER(diag.long_title) LIKE '%hemiplegia%' OR LOWER(diag.long_title) LIKE '%paraplegia%', 1, 0)) AS charlson_hemiplegia,
    MAX(IF(LOWER(diag.long_title) LIKE '%renal failure%' OR LOWER(diag.long_title) LIKE '%chronic kidney%' OR LOWER(diag.long_title) LIKE '%chronic renal%', 1, 0)) AS charlson_renal,
    MAX(IF(LOWER(diag.long_title) LIKE '%malignant%' OR LOWER(diag.long_title) LIKE '%malignancy%' OR LOWER(diag.long_title) LIKE '%carcinoma%' OR LOWER(diag.long_title) LIKE '%neoplasm%' OR LOWER(diag.long_title) LIKE '%tumor%', 1, 0)) AS charlson_any_tumor,
    MAX(IF(LOWER(diag.long_title) LIKE '%metastatic%' OR LOWER(diag.long_title) LIKE '%secondary malignant%' OR LOWER(diag.long_title) LIKE '%metastasis%', 1, 0)) AS charlson_metastatic,
    MAX(IF(LOWER(diag.long_title) LIKE '%leukemia%' OR LOWER(diag.long_title) LIKE '%lymphoma%', 1, 0)) AS charlson_hemonc,
    MAX(IF(LOWER(diag.long_title) LIKE '%hiv%' OR LOWER(diag.long_title) LIKE '%aids%', 1, 0)) AS charlson_aids,

    -- Major complications (approximate by diagnosis keywords)
    MAX(IF(LOWER(diag.long_title) LIKE '%stroke%' OR LOWER(diag.long_title) LIKE '%cerebrovascular%', 1, 0)) AS comp_stroke,
    MAX(IF(LOWER(diag.long_title) LIKE '%acute renal failure%' OR LOWER(diag.long_title) LIKE '%acute kidney%' OR LOWER(diag.long_title) LIKE '%acute tubular necrosis%' OR LOWER(diag.long_title) LIKE '%akf%' OR LOWER(diag.long_title) LIKE '%acute kidney injury%', 1, 0)) AS comp_aki,
    MAX(IF(LOWER(diag.long_title) LIKE '%cardiogenic shock%' OR LOWER(diag.long_title) LIKE '%shock%' OR LOWER(diag.long_title) LIKE '%cardiac arrest%', 1, 0)) AS comp_shock_arrest,
    MAX(IF(LOWER(diag.long_title) LIKE '%hemorrhag%' OR LOWER(diag.long_title) LIKE '%bleeding%' OR LOWER(diag.long_title) LIKE '%gastrointestinal hemorrhage%' OR LOWER(diag.long_title) LIKE '%haemorrhage%', 1, 0)) AS comp_bleed,
    MAX(IF(LOWER(diag.long_title) LIKE '%reinfarction%' OR (LOWER(diag.long_title) LIKE '%myocardial infarction%' AND LOWER(diag.long_title) LIKE '%reinfarct%'), 1, 0)) AS comp_reinfarct

  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND SAFE_CAST(d.icd_version AS STRING) = SAFE_CAST(diag.icd_version AS STRING)
  GROUP BY d.hadm_id
),

-- compute Charlson score by summing weighted flags (approximate)
diag_charlson AS (
  SELECT
    hadm_id,
    -- weights per Charlson index
    (IFNULL(charlson_mi,0) * 1) +
    (IFNULL(charlson_chf,0) * 1) +
    (IFNULL(charlson_pvd,0) * 1) +
    (IFNULL(charlson_cvd,0) * 1) +
    (IFNULL(charlson_dementia,0) * 1) +
    (IFNULL(charlson_copd,0) * 1) +
    (IFNULL(charlson_rheumatic,0) * 1) +
    (IFNULL(charlson_pud,0) * 1) +
    -- mild liver disease weight 1, moderate/severe weight 3 -> if mod/sev present, count 3, else if mild present 1
    (CASE WHEN IFNULL(charlson_liver_modsev,0) = 1 THEN 3 WHEN IFNULL(charlson_liver_mild,0) = 1 THEN 1 ELSE 0 END) +
    -- diabetes with complications 2, without 1
    (CASE WHEN IFNULL(charlson_dm_with_comp,0) = 1 THEN 2 WHEN IFNULL(charlson_dm_no_comp,0) = 1 THEN 1 ELSE 0 END) +
    (IFNULL(charlson_hemiplegia,0) * 2) +
    (IFNULL(charlson_renal,0) * 2) +
    -- tumor 2, metastatic 6; if metastatic present, give metastatic weight (6) and avoid double-counting both
    (CASE WHEN IFNULL(charlson_metastatic,0) = 1 THEN 6 WHEN IFNULL(charlson_any_tumor,0) = 1 THEN 2 ELSE 0 END) +
    (IFNULL(charlson_hemonc,0) * 2) +
    (IFNULL(charlson_aids,0) * 6) AS charlson_score,
    -- composite major complication flag (any of the defined complications)
    GREATEST(IFNULL(comp_stroke,0), IFNULL(comp_aki,0), IFNULL(comp_shock_arrest,0), IFNULL(comp_bleed,0), IFNULL(comp_reinfarct,0)) AS any_major_complication,
    -- individual complication flags preserved if needed
    IFNULL(comp_stroke,0) AS comp_stroke,
    IFNULL(comp_aki,0) AS comp_aki,
    IFNULL(comp_shock_arrest,0) AS comp_shock_arrest,
    IFNULL(comp_bleed,0) AS comp_bleed,
    IFNULL(comp_reinfarct,0) AS comp_reinfarct
  FROM diag_flags
),

-- Admissions joined with patient and ICU existence and charlson/complication flags
admissions_enriched AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod,
    -- LOS in days (integer)
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    IFNULL(dc.charlson_score, 0) AS charlson_score,
    IFNULL(dc.any_major_complication, 0) AS any_major_complication,
    dc.comp_stroke, dc.comp_aki, dc.comp_shock_arrest, dc.comp_bleed, dc.comp_reinfarct
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN diag_charlson dc
    ON a.hadm_id = dc.hadm_id
  JOIN icu_admissions i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- Identify admissions with AMI by searching diagnoses for AMI-related keywords
ami_flag AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND SAFE_CAST(d.icd_version AS STRING) = SAFE_CAST(diag.icd_version AS STRING)
  WHERE LOWER(IFNULL(diag.long_title, '')) LIKE '%myocardial infarction%'
     OR LOWER(IFNULL(diag.long_title, '')) LIKE '%acute mi%'
     OR LOWER(IFNULL(diag.long_title, '')) LIKE '%acute myocardial infarction%'
),

-- Cohorts: AMI vs age-matched general (females 68-78 with ICU stay)
cohort_ami AS (
  SELECT a.*
  FROM admissions_enriched a
  JOIN ami_flag am ON a.hadm_id = am.hadm_id
),
cohort_general AS (
  SELECT a.*
  FROM admissions_enriched a
  LEFT JOIN ami_flag am ON a.hadm_id = am.hadm_id
  WHERE am.hadm_id IS NULL  -- exclude AMI admissions
),

-- Summary statistics function-style aggregations for AMI and General cohorts
ami_stats AS (
  SELECT
    COUNT(*) AS n_admissions,
    -- quartiles: APPROX_QUANTILES returns array: [min, Q1, median, Q3, max] when num_buckets=4
    APPROX_QUANTILES(charlson_score, 4) AS charlson_quants,
    SUM(CASE WHEN (dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) BETWEEN 0 AND 90) OR (hospital_expire_flag = 1 AND dod IS NULL) THEN 1 ELSE 0 END) AS deaths_90d,
    SUM(CASE WHEN any_major_complication = 1 THEN 1 ELSE 0 END) AS major_complications,
    -- LOS among hospital survivors only
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 4) AS survivor_los_quants
  FROM cohort_ami
),
general_stats AS (
  SELECT
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(charlson_score, 4) AS charlson_quants,
    SUM(CASE WHEN (dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) BETWEEN 0 AND 90) OR (hospital_expire_flag = 1 AND dod IS NULL) THEN 1 ELSE 0 END) AS deaths_90d,
    SUM(CASE WHEN any_major_complication = 1 THEN 1 ELSE 0 END) AS major_complications,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 4) AS survivor_los_quants
  FROM cohort_general
),

-- For percentile: get full distribution of charlson in general cohort and compare AMI median
general_charlson_distribution AS (
  SELECT charlson_score
  FROM cohort_general
)

SELECT
  -- AMI cohort results
  'AMI cohort (female, age 68-78, with ICU stay)' AS cohort,
  a.n_admissions AS ami_n,
  -- Charlson median and IQR
  a.charlson_quants[OFFSET(2)] AS ami_charlson_median,
  a.charlson_quants[OFFSET(1)] AS ami_charlson_q1,
  a.charlson_quants[OFFSET(3)] AS ami_charlson_q3,
  -- 90-day mortality rate
  SAFE_DIVIDE(a.deaths_90d, a.n_admissions) AS ami_90d_mortality_rate,
  -- major complication rate
  SAFE_DIVIDE(a.major_complications, a.n_admissions) AS ami_major_complication_rate,
  -- survivor LOS median (days) and IQR
  a.survivor_los_quants[OFFSET(2)] AS ami_survivor_los_median_days,
  a.survivor_los_quants[OFFSET(1)] AS ami_survivor_los_q1_days,
  a.survivor_los_quants[OFFSET(3)] AS ami_survivor_los_q3_days,

  -- General cohort results
  g.n_admissions AS general_n,
  g.charlson_quants[OFFSET(2)] AS general_charlson_median,
  g.charlson_quants[OFFSET(1)] AS general_charlson_q1,
  g.charlson_quants[OFFSET(3)] AS general_charlson_q3,
  SAFE_DIVIDE(g.deaths_90d, g.n_admissions) AS general_90d_mortality_rate,
  SAFE_DIVIDE(g.major_complications, g.n_admissions) AS general_major_complication_rate,
  g.survivor_los_quants[OFFSET(2)] AS general_survivor_los_median_days,
  g.survivor_los_quants[OFFSET(1)] AS general_survivor_los_q1_days,
  g.survivor_los_quants[OFFSET(3)] AS general_survivor_los_q3_days,

  -- Risk percentile: proportion of general cohort with Charlson <= AMI median Charlson
  (SELECT SAFE_DIVIDE(COUNTIF(charlson_score <= a.charlson_quants[OFFSET(2)]), COUNT(*)) FROM general_charlson_distribution) AS ami_median_charlson_percentile_in_general

FROM ami_stats a CROSS JOIN general_stats g;