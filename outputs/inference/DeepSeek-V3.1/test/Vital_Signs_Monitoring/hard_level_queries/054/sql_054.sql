WITH respiratory_failure AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE d.long_title LIKE '%acute respiratory failure%'
    AND diag.icd_code LIKE 'J96.0%'
),
first_icu_stay AS (
  SELECT 
    ie.subject_id, ie.hadm_id, ie.stay_id,
    ie.intime, ie.outtime,
    DATETIME_ADD(ie.intime, INTERVAL 72 HOUR) AS end_72hr,
    ie.los,
    adm.deathtime IS NOT NULL AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
),
cohort_rf AS (
  SELECT fis.*
  FROM first_icu_stay fis
  INNER JOIN respiratory_failure rf
    ON fis.hadm_id = rf.hadm_id
),
cohort_general AS (
  SELECT fis.*
  FROM first_icu_stay fis
  LEFT JOIN respiratory_failure rf
    ON fis.hadm_id = rf.hadm_id
  WHERE rf.hadm_id IS NULL
),
vitals_rf AS (
  SELECT 
    ce.stay_id,
    COUNT(*) AS total_measurements,
    SUM(CASE WHEN ce.itemid = 220181 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_rf crf
    ON ce.stay_id = crf.stay_id
  WHERE ce.itemid IN (220181, 220045)
    AND ce.charttime >= crf.intime
    AND ce.charttime <= crf.end_72hr
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
burden_rf AS (
  SELECT 
    stay_id,
    (map_low_count / total_measurements) AS map_burden,
    (hr_high_count / total_measurements) AS hr_burden,
    (map_low_count / total_measurements) + (hr_high_count / total_measurements) AS composite_score
  FROM vitals_rf
),
vitals_general AS (
  SELECT 
    ce.stay_id,
    COUNT(*) AS total_measurements,
    SUM(CASE WHEN ce.itemid = 220181 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_general cg
    ON ce.stay_id = cg.stay_id
  WHERE ce.itemid IN (220181, 220045)
    AND ce.charttime >= cg.intime
    AND ce.charttime <= cg.end_72hr
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
burden_general AS (
  SELECT 
    stay_id,
    (map_low_count / total_measurements) + (hr_high_count / total_measurements) AS composite_score
  FROM vitals_general
),
rf_quantiles AS (
  SELECT 
    APPROX_QUANTILES(composite_score, 100) AS quantiles
  FROM burden_rf
),
rf_stats AS (
  SELECT
    quantiles[OFFSET(25)] AS p25,
    quantiles[OFFSET(50)] AS median,
    quantiles[OFFSET(75)] AS p75,
    quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr
  FROM rf_quantiles
)
SELECT 
  p25,
  median,
  p75,
  iqr,
  (SELECT AVG(composite_score) FROM burden_general) AS avg_composite_general,
  (SELECT AVG(los) FROM cohort_rf) AS avg_los_rf,
  (SELECT AVG(los) FROM cohort_general) AS avg_los_general,
  (SELECT AVG(CAST(mortality AS INT)) FROM cohort_rf) AS mortality_rate_rf,
  (SELECT AVG(CAST(mortality AS INT)) FROM cohort_general) AS mortality_rate_general
FROM rf_stats;