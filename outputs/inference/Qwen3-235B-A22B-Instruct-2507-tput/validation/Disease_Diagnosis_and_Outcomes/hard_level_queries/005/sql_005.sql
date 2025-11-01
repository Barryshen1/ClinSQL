WITH eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age AS age_at_admit,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.dod,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON adm.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age BETWEEN 43 AND 53
),
heart_failure_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%heart failure%'
),
first_admission AS (
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM eligible_patients
  GROUP BY subject_id
),
cohort AS (
  SELECT
    ep.*
  FROM eligible_patients ep
  INNER JOIN first_admission fa
    ON ep.subject_id = fa.subject_id AND ep.admittime = fa.first_admittime
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON ep.hadm_id = di.hadm_id
  INNER JOIN heart_failure_codes hfc
    ON di.icd_code = hfc.icd_code
),
all_diagnoses AS (
  SELECT
    di.hadm_id,
    di.icd_code,
    di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
),
comorbidity_categories AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN SUBSTR(icd_code, 1, 3) = 'E11' THEN 1 ELSE 0 END) AS diabetes,
    MAX(CASE WHEN SUBSTR(icd_code, 1, 3) = 'J44' THEN 1 ELSE 0 END) AS chronic_pulmonary,
    MAX(CASE WHEN SUBSTR(icd_code, 1, 3) = 'N18' THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN SUBSTR(icd_code, 1, 3) IN ('I85', 'K70') OR icd_code = 'I98.2' THEN 1 ELSE 0 END) AS liver,
    MAX(CASE WHEN SUBSTR(icd_code, 1, 1) = 'C' THEN 1 ELSE 0 END) AS cancer,
    MAX(CASE WHEN SUBSTR(icd_code, 1, 2) = 'I6' THEN 1 ELSE 0 END) AS cerebrovascular,
    MAX(CASE WHEN SUBSTR(icd_code, 1, 3) = 'I73' THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN SUBSTR(icd_code, 1, 3) = 'M32' THEN 1 ELSE 0 END) AS rheumatologic,
    MAX(CASE WHEN icd_code = 'B20' THEN 1 ELSE 0 END) AS aids,
    MAX(CASE WHEN SUBSTR(icd_code, 1, 3) IN ('C78', 'C79', 'C80') THEN 1 ELSE 0 END) AS metastatic_cancer
  FROM all_diagnoses
  GROUP BY hadm_id
),
comorbidity_counts AS (
  SELECT
    hadm_id,
    diabetes + chronic_pulmonary + renal + liver + cancer + cerebrovascular + pvd + rheumatologic + aids + metastatic_cancer AS comorbidity_count
  FROM comorbidity_categories
),
complication_codes AS (
  SELECT 'N17' AS prefix UNION ALL
  SELECT 'J96.0' UNION ALL
  SELECT 'A41.9' UNION ALL
  SELECT 'R65.20' UNION ALL
  SELECT 'I46' UNION ALL
  SELECT 'I63' UNION ALL
  SELECT 'G45'
),
major_complication AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  CROSS JOIN complication_codes cc
  WHERE (di.icd_version = 10 AND di.icd_code LIKE CONCAT(cc.prefix, '%'))
     OR (di.icd_version = 9 AND di.icd_code IN ('584', '518.81', '038.9', '785.51', '427.5', '434', '435'))
),
cohort_outcomes AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    COALESCE(cc.comorbidity_count, 0) AS risk_score,
    CASE
      WHEN c.dod IS NOT NULL AND DATETIME_DIFF(c.dod, c.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    CASE WHEN mc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS major_complication,
    CASE
      WHEN c.hospital_expire_flag = 0 THEN DATETIME_DIFF(c.dischtime, c.admittime, DAY)
      ELSE NULL
    END AS los_hospital_survivors
  FROM cohort c
  LEFT JOIN comorbidity_counts cc ON c.hadm_id = cc.hadm_id
  LEFT JOIN major_complication mc ON c.hadm_id = mc.hadm_id
),
reference_population AS (
  SELECT
    ep.hadm_id,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count
  FROM eligible_patients ep
  INNER JOIN first_admission fa
    ON ep.subject_id = fa.subject_id AND ep.admittime = fa.first_admittime
  LEFT JOIN comorbidity_counts cc ON ep.hadm_id = cc.hadm_id
),
cohort_stats AS (
  SELECT
    APPROX_QUANTILES(risk_score, 1000)[OFFSET(500)] AS median_risk,
    APPROX_QUANTILES(risk_score, 1000)[OFFSET(250)] AS q1_risk,
    APPROX_QUANTILES(risk_score, 1000)[OFFSET(750)] AS q3_risk,
    AVG(CAST(mortality_30d AS FLOAT64)) AS mortality_rate,
    AVG(CAST(major_complication AS FLOAT64)) AS complication_rate,
    AVG(los_hospital_survivors) AS avg_los_survivors
  FROM cohort_outcomes
),
reference_stats AS (
  SELECT
    comorbidity_count,
    PERCENT_RANK();