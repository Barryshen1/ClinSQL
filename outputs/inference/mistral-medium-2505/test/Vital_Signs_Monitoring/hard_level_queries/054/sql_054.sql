WITH
-- Get male patients aged 82-92 with acute respiratory failure
respiratory_failure_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND d.icd_code IN ('J96.0', 'J96.00', 'J96.01', 'J96.02', 'J96.20', 'J96.21', 'J96.22', '518.81')
),

-- Get all male ICU patients for comparison
all_male_icu_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),

-- Calculate MAP and HR burdens for respiratory failure patients
rf_vitals AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.stay_id,
    r.intime,
    r.outtime,
    r.los,
    r.hospital_expire_flag,
    -- Calculate time with MAP < 65
    SUM(CASE WHEN c.itemid = 220050 AND c.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    COUNT(CASE WHEN c.itemid = 220050 THEN 1 END) AS map_total_count,
    -- Calculate time with HR > 100
    SUM(CASE WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high_count,
    COUNT(CASE WHEN c.itemid = 220045 THEN 1 END) AS hr_total_count
  FROM respiratory_failure_patients r
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON r.subject_id = c.subject_id AND r.hadm_id = c.hadm_id AND r.stay_id = c.stay_id
  WHERE TIMESTAMP_DIFF(c.charttime, r.intime, HOUR) BETWEEN 0 AND 72
  GROUP BY r.subject_id, r.hadm_id, r.stay_id, r.intime, r.outtime, r.los, r.hospital_expire_flag
),

-- Calculate MAP and HR burdens for all male ICU patients
all_vitals AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    a.intime,
    a.outtime,
    a.los,
    a.hospital_expire_flag,
    -- Calculate time with MAP < 65
    SUM(CASE WHEN c.itemid = 220050 AND c.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    COUNT(CASE WHEN c.itemid = 220050 THEN 1 END) AS map_total_count,
    -- Calculate time with HR > 100
    SUM(CASE WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high_count,
    COUNT(CASE WHEN c.itemid = 220045 THEN 1 END) AS hr_total_count
  FROM all_male_icu_patients a
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id AND a.stay_id = c.stay_id
  WHERE TIMESTAMP_DIFF(c.charttime, a.intime, HOUR) BETWEEN 0 AND 72
  GROUP BY a.subject_id, a.hadm_id, a.stay_id, a.intime, a.outtime, a.los, a.hospital_expire_flag
),

-- Calculate composite scores for respiratory failure patients
rf_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    hospital_expire_flag,
    (map_low_count / NULLIF(map_total_count, 0)) AS map_burden,
    (hr_high_count / NULLIF(hr_total_count, 0)) AS hr_burden,
    ((map_low_count / NULLIF(map_total_count, 0)) + (hr_high_count / NULLIF(hr_total_count, 0))) AS composite_score
  FROM rf_vitals
),

-- Calculate composite scores for all male ICU patients
all_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    hospital_expire_flag,
    (map_low_count / NULLIF(map_total_count, 0)) AS map_burden,
    (hr_high_count / NULLIF(hr_total_count, 0)) AS hr_burden,
    ((map_low_count / NULLIF(map_total_count, 0)) + (hr_high_count / NULLIF(hr_total_count, 0))) AS composite_score
  FROM all_vitals
)

-- Final results
SELECT
  'Respiratory Failure Patients' AS cohort,
  COUNT(*) AS patient_count,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] AS p75,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] - APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS iqr,
  AVG(map_burden) AS avg_map_burden,
  AVG(hr_burden) AS avg_hr_burden,
  AVG(los) AS avg_icu_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
FROM rf_scores

UNION ALL

SELECT
  'All Male ICU Patients' AS cohort,
  COUNT(*) AS patient_count,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] AS p75,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] - APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS iqr,
  AVG(map_burden) AS avg_map_burden,
  AVG(hr_burden) AS avg_hr_burden,
  AVG(los) AS avg_icu_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
FROM all_scores
ORDER BY cohort;