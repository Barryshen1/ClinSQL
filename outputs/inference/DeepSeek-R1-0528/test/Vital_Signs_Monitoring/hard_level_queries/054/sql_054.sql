WITH first_icu_stay AS (
  SELECT 
    subject_id, hadm_id, stay_id, intime, outtime, los,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS stay_order
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
-- Target cohort: Male, age 82-92, with acute respiratory failure
target_cohort AS (
  SELECT 
    fs.subject_id, fs.hadm_id, fs.stay_id, fs.intime, fs.outtime, fs.los,
    adm.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age
  FROM first_icu_stay fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON fs.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fs.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON fs.hadm_id = diag.hadm_id
  WHERE 
    fs.stay_order = 1
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 82 AND 92
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '51881') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'J96%')
    )
),
-- General ICU cohort (all first stays)
general_cohort AS (
  SELECT 
    fs.subject_id, fs.hadm_id, fs.stay_id, fs.intime, fs.outtime, fs.los,
    adm.hospital_expire_flag
  FROM first_icu_stay fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON fs.hadm_id = adm.hadm_id
  WHERE fs.stay_order = 1
),
-- Combine cohorts and pre-join for measurement filtering
cohorts_combined AS (
  SELECT 
    stay_id, intime, 'target' AS cohort, 
    los, hospital_expire_flag
  FROM target_cohort
  UNION ALL
  SELECT 
    stay_id, intime, 'general' AS cohort,
    los, hospital_expire_flag
  FROM general_cohort
),
-- Relevant MAP/HR measurements in first 72 hours
measurements AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    CASE 
      WHEN ce.itemid IN (220052, 220181, 225312) THEN 'MAP'
      WHEN ce.itemid IN (220045, 211) THEN 'HR'
    END AS param,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohorts_combined c 
    ON ce.stay_id = c.stay_id
  WHERE 
    ce.itemid IN (220052, 220181, 225312, 220045, 211)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
),
-- Calculate burdens per stay
burdens AS (
  SELECT 
    stay_id,
    COUNTIF(param = 'MAP') AS total_map,
    COUNTIF(param = 'MAP' AND valuenum < 65) AS low_map,
    COUNTIF(param = 'HR') AS total_hr,
    COUNTIF(param = 'HR' AND valuenum > 100) AS high_hr
  FROM measurements
  GROUP BY stay_id
),
-- Compute proportions and composite score
cohort_burdens AS (
  SELECT 
    c.stay_id, c.cohort, c.los, c.hospital_expire_flag,
    IF(total_map > 0, low_map / total_map, NULL) AS burden_map,
    IF(total_hr > 0, high_hr / total_hr, NULL) AS burden_hr,
    IF(total_map > 0, low_map / total_map, 0) + 
    IF(total_hr > 0, high_hr / total_hr, 0) AS composite_score
  FROM cohorts_combined c
  LEFT JOIN burdens b
    ON c.stay_id = b.stay_id
),
-- Split into target and general for final results
target_burdens AS (
  SELECT * FROM cohort_burdens WHERE cohort = 'target'
),
general_burdens AS (
  SELECT * FROM cohort_burdens WHERE cohort = 'general'
)

-- Part 1: Composite score percentiles for target cohort (5 columns)
SELECT 
  'target_percentiles' AS result_type,
  APPROX_QUANTILES(composite_score, 100)[OFFSET(25)] AS p25_composite,
  APPROX_QUANTILES(composite_score, 100)[OFFSET(50)] AS median_composite,
  APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] AS p75_composite,
  APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] - APPROX_QUANTILES(composite_score, 100)[OFFSET(25)] AS iqr_composite
FROM target_burdens
WHERE composite_score IS NOT NULL

UNION ALL

-- Separator row (5 columns)
SELECT 
  '----' AS result_type,
  NULL, NULL, NULL, NULL

UNION ALL

-- Part 2: Comparison between cohorts (5 columns)
SELECT 
  cohort AS result_type,
  AVG(burden_map) AS avg_burden_map,
  AVG(burden_hr) AS avg_burden_hr,
  AVG(los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_burdens
GROUP BY cohort;