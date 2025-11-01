WITH acs_patients AS (
  -- Female patients aged 53-63 with ACS
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
    AND dx.icd_version = 10
    AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I24%')
),

controls AS (
  -- Age-matched female controls without ACS
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
    AND adm.hadm_id NOT IN (SELECT hadm_id FROM acs_patients)
),

labs_acs AS (
  -- Labs for ACS patients within 72 hours
  SELECT le.subject_id, le.hadm_id, dli.category,
    MAX(CASE 
      WHEN dli.category = 'Troponin' AND le.valuenum > 0.1 THEN 1
      WHEN dli.category = 'Potassium' AND (le.valuenum < 3.0 OR le.valuenum > 5.5) THEN 1
      WHEN dli.category = 'Sodium' AND (le.valuenum < 130 OR le.valuenum > 150) THEN 1
      WHEN dli.category = 'Creatinine' AND le.valuenum > 1.3 THEN 1
      WHEN dli.category = 'Glucose' AND (le.valuenum < 70 OR le.valuenum > 200) THEN 1
      WHEN dli.category = 'INR' AND le.valuenum > 1.5 THEN 1
      WHEN dli.category = 'Hemoglobin' AND le.valuenum < 10 THEN 1
      ELSE 0
    END) AS is_critical
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN acs_patients adm
    ON le.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
    AND dli.category IN ('Troponin', 'Potassium', 'Sodium', 'Creatinine', 'Glucose', 'INR', 'Hemoglobin')
    AND le.valuenum IS NOT NULL
  GROUP BY le.subject_id, le.hadm_id, dli.category
),

labs_controls AS (
  -- Labs for controls within 72 hours
  SELECT le.subject_id, le.hadm_id, dli.category,
    MAX(CASE 
      WHEN dli.category = 'Troponin' AND le.valuenum > 0.1 THEN 1
      WHEN dli.category = 'Potassium' AND (le.valuenum < 3.0 OR le.valuenum > 5.5) THEN 1
      WHEN dli.category = 'Sodium' AND (le.valuenum < 130 OR le.valuenum > 150) THEN 1
      WHEN dli.category = 'Creatinine' AND le.valuenum > 1.3 THEN 1
      WHEN dli.category = 'Glucose' AND (le.valuenum < 70 OR le.valuenum > 200) THEN 1
      WHEN dli.category = 'INR' AND le.valuenum > 1.5 THEN 1
      WHEN dli.category = 'Hemoglobin' AND le.valuenum < 10 THEN 1
      ELSE 0
    END) AS is_critical
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN controls adm
    ON le.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
    AND dli.category IN ('Troponin', 'Potassium', 'Sodium', 'Creatinine', 'Glucose', 'INR', 'Hemoglobin')
    AND le.valuenum IS NOT NULL
  GROUP BY le.subject_id, le.hadm_id, dli.category
),

instability_acs AS (
  -- Instability score for ACS patients
  SELECT subject_id, hadm_id, COUNT(DISTINCT category) AS instability_score
  FROM labs_acs
  WHERE is_critical = 1
  GROUP BY subject_id, hadm_id
),

instability_controls AS (
  -- Instability score for controls
  SELECT subject_id, hadm_id, COUNT(DISTINCT category) AS instability_score
  FROM labs_controls
  WHERE is_critical = 1
  GROUP BY subject_id, hadm_id
),

acs_with_score AS (
  -- Combine ACS patients with their instability score (default 0 if no critical labs)
  SELECT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag,
    COALESCE(ia.instability_score, 0) AS instability_score
  FROM acs_patients adm
  LEFT JOIN instability_acs ia
    ON adm.hadm_id = ia.hadm_id
),

quartiles AS (
  -- Assign quartiles based on instability score
  SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag, instability_score,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM acs_with_score
)

-- First result: ACS patients by quartile
SELECT 
  'ACS' AS cohort,
  quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent,
  ROUND(AVG(DATETIME_DIFF(COALESCE(dischtime, admittime), admittime, DAY)), 2) AS avg_los_days
FROM quartiles
GROUP BY quartile
ORDER BY quartile;

-- Second result: Lab comparison between ACS and controls
SELECT 
  category,
  ROUND(100 * SUM(CASE WHEN cohort = 'ACS' THEN is_critical ELSE 0 END) / COUNT(DISTINCT CASE WHEN cohort = 'ACS' THEN hadm_id END), 2) AS acs_critical_rate,
  ROUND(100 * SUM(CASE WHEN cohort = 'Control' THEN is_critical ELSE 0 END) / COUNT(DISTINCT CASE WHEN cohort = 'Control' THEN hadm_id END), 2) AS control_critical_rate
FROM (
  SELECT 'ACS' AS cohort, hadm_id, category, is_critical FROM labs_acs
  UNION ALL
  SELECT 'Control' AS cohort, hadm_id, category, is_critical FROM labs_controls
) combined
GROUP BY category
ORDER BY category;