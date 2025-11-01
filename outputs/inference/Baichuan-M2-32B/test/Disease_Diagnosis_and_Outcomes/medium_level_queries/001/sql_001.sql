WITH base_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATEDIFF(a.dischtime, a.admittime) AS los_days,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
),
adhf_diagnoses AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.icd_version = 10
    AND d.icd_code IN ('I10', 'I11', 'I13', 'I42', 'I50') -- ADHF ICD-10 codes
),
ckd_codes AS (
  SELECT * FROM UNNEST([
    'N18', 'N19', 'N25', 'N26', 'N27', 'N29', 
    'E87.2', 'E87.3', 'E87.4', 'E87.5', 'E87.6', 'E87.7', 'E87.8', 'E87.9',
    'E11.2', 'E11.21', 'E11.22', 'E11.23', 'E11.24', 'E11.25', 'E11.26', 'E11.29',
    'E10.2', 'E10.21', 'E10.22', 'E10.23', 'E10.24', 'E10.25', 'E10.26', 'E10.29',
    'E13.2', 'E13.21', 'E13.22', 'E13.23', 'E13.24', 'E13.25', 'E13.26', 'E13.29',
    'E14.2', 'E14.21', 'E14.22', 'E14.23', 'E14.24', 'E14.25', 'E14.26', 'E14.29',
    'E15.2', 'E15.21', 'E15.22', 'E15.23', 'E15.24', 'E15.25', 'E15.26', 'E15.29',
    'E16.2', 'E16.21', 'E16.22', 'E16.23', 'E16.24', 'E16.25', 'E16.26', 'E16.29',
    'E17.2', 'E17.21', 'E17.22', 'E17.23', 'E17.24', 'E17.25', 'E17.26', 'E17.29',
    'E18.2', 'E18.21', 'E18.22', 'E18.23', 'E18.24', 'E18.25', 'E18.26', 'E18.29',
    'E19.2', 'E19.21', 'E19.22', 'E19.23', 'E19.24', 'E19.25', 'E19.26', 'E19.29',
    'E20.2', 'E20.21', 'E20.22', 'E20.23', 'E20.24', 'E20.25', 'E20.26', 'E20.29',
    'E21.2', 'E21.21', 'E21.22', 'E21.23', 'E21.24', 'E21.25', 'E21.26', 'E21.29',
    'E22.2', 'E22.21', 'E22.22', 'E22.23', 'E22.24', 'E22.25', 'E22.26', 'E22.29',
    'E23.2', 'E23.21', 'E23.22', 'E23.23', 'E23.24', 'E23.25', 'E23.26', 'E23.29',
    'E24.2', 'E24.21', 'E24.22', 'E24.23', 'E24.24', 'E24.25', 'E24.26', 'E24.29',
    'E25.2', 'E25.21', 'E25.22', 'E25.23', 'E25.24', 'E25.25', 'E25.26', 'E25.29',
    'E26.2', 'E26.21', 'E26.22', 'E26.23', 'E26.24', 'E26.25', 'E26.26', 'E26.29',
    'E27.2', 'E27.21', 'E27.22', 'E27.23', 'E27.24', 'E27.25', 'E27.26', 'E27.29',
    'E28.2', 'E28.21', 'E28.22', 'E28.23', 'E28.24', 'E28.25', 'E28.26', 'E28.29',
    'E29.2', 'E29.21', 'E29.22', 'E29.23', 'E29.24', 'E29.25', 'E29.26', 'E29.29',
    'E30.2', 'E30.21', 'E30.22', 'E30.23', 'E30.24', 'E30.25', 'E30.26', 'E30.29',
    'E31.2', 'E31.21', 'E31.22', 'E31.23', 'E31.24', 'E31.25', 'E31.26', 'E31.29',
    'E32.2', 'E32.21', 'E32.22', 'E32.23', 'E32.24', 'E32.25', 'E32.26', 'E32.29',
    'E33.2', 'E33.21', 'E33.22', 'E33.23', 'E33.24', 'E33.25', 'E33.26', 'E33.29',
    'E34.2', 'E34.21', 'E34.22', 'E34.23', 'E34.24', 'E34.25', 'E34.26', 'E34.29',
    'E35.2', 'E35.21', 'E35.22', 'E35.23', 'E35.24', 'E35.25', 'E35.26', 'E35.29',
    'E36.2', 'E36.21', 'E36.22', 'E36.23', 'E36.24', 'E36.25', 'E36.26', 'E36.29',
    'E37.2', 'E37.21', 'E37.22', 'E37.23', 'E37.24', 'E37.25', 'E37.26', 'E37.29',
    'E38.2', 'E38.21', 'E38.22', 'E38.23', 'E38.24', 'E38.25', 'E38.26', 'E38.29',
    'E39.2', 'E39.21', 'E39.22', 'E39.23', 'E39.24', 'E39.25', 'E39.26', 'E39.29',
    'E40.2', 'E40.21', 'E40.22', 'E40.23', 'E40.24', 'E40.25', 'E40.26', 'E40.29',
    'E41.2', 'E41.21', 'E41.22', 'E41.23', 'E41.24', 'E41.25', 'E41.26', 'E41.29',
    'E42.2', 'E42.21', 'E42.22', 'E42.23', 'E42.24', 'E42.25', 'E42.26', 'E42.29',
    'E43.2', 'E43.21', 'E43.22', 'E43.23', 'E43.24', 'E43.25', 'E43.26', 'E43.29',
    'E44.2', 'E44.21', 'E44.22', 'E44.23', 'E44.24', 'E44.25', 'E44.26', 'E44.29',
    'E45.2', 'E45.21', 'E45.22', 'E45.23', 'E45.24', 'E45.25', 'E45.26', 'E45.29',
    'E46.2', 'E46.21', 'E46.22', 'E46.23', 'E46.24', 'E46.25', 'E46.26', 'E46.29',
    'E47.2', 'E47.21', 'E47.22', 'E47.23', 'E47.24', 'E47.25', 'E47.26', 'E47.29',
    'E48.2', 'E48.21', 'E48.22', 'E48.23', 'E48.24', 'E48.25', 'E48.26', 'E48.29',
    'E49.2', 'E49.21'
  ]) AS code
),
diabetes_codes AS (
  SELECT * FROM UNNEST([
    'E10', 'E11', 'E12', 'E13', 'E14', 'E15', 'E16', 'E17', 'E18', 'E19',
    'E20', 'E21', 'E22', 'E23', 'E24', 'E25', 'E26', 'E27', 'E28', 'E29',
    'E30', 'E31', 'E32', 'E33', 'E34', 'E35', 'E36', 'E37', 'E38', 'E39',
    'E40', 'E41', 'E42', 'E43', 'E44', 'E45', 'E46', 'E47', 'E48', 'E49',
    'E50', 'E51', 'E52', 'E53', 'E54', 'E55', 'E56', 'E57', 'E58', 'E59',
    'E60', 'E61', 'E62', 'E63', 'E64', 'E65', 'E66', 'E67', 'E68', 'E69',
    'E70', 'E71', 'E72', 'E73', 'E74', 'E75', 'E76', 'E77', 'E78', 'E79',
    'E80', 'E81', 'E82', 'E83', 'E84', 'E85', 'E86', 'E87', 'E88', 'E89',
    'E90', 'E91', 'E92', 'E93', 'E94', 'E95', 'E96', 'E97', 'E98', 'E99'
  ]) AS code
),
ckd_diagnoses AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN ckd_codes c ON d.icd_code = c.code
  WHERE d.icd_version = 10
),
diabetes_diagnoses AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN diabetes_codes dc ON d.icd_code LIKE CONCAT(dc.code, '%') -- Use LIKE to match prefixes
  WHERE d.icd_version = 10
),
icu_day1 AS (
  SELECT DISTINCT
    a.hadm_id,
    CASE WHEN DATE(i.intime) = DATE(a.admittime) THEN 1 ELSE 0 END AS icu_day1
  FROM base_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id
    AND a.hadm_id = i.hadm_id
),
final_cohort AS (
  SELECT
    b.hadm_id,
    b.hospital_expire_flag,
    b.los_days,
    CASE WHEN b.los_days <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_category,
    i.icu_day1,
    CASE WHEN d.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes,
    CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd
  FROM base_admissions b
  INNER JOIN adhf_diagnoses ad ON b.hadm_id = ad.hadm_id
  LEFT JOIN icu_day1 i ON b.hadm_id = i.hadm_id
  LEFT JOIN diabetes_diagnoses d ON b.hadm_id = d.hadm_id
  LEFT JOIN ckd_diagnoses c ON b.hadm_id = c.hadm_id
)
SELECT
  los_category,
  icu_day1,
  COUNT(DISTINCT hadm_id) AS total_patients,
  SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id) AS mortality_percent,
  SUM(has_diabetes) * 100.0 / COUNT(DISTINCT hadm_id) AS diabetes_prevalence_percent,
  SUM(has_ckd) * 100.0 / COUNT(DISTINCT hadm_id) AS ckd_prevalence_percent
FROM final_cohort
GROUP BY los_category, icu_day1
ORDER BY los_category, icu_day1;