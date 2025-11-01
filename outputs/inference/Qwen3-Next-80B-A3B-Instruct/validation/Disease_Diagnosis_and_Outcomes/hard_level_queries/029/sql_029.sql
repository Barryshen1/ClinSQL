WITH pneumonia_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu_stay,
    COUNT(DISTINCT CASE WHEN d.icd_code NOT IN (
      '486', '485', '482.9', '482.8', '482.81', '482.82', '482.83', '482.84', '482.89', '482.9',
      'J18.9', 'J18.0', 'J18.1', 'J18.2', 'J18.3', 'J18.4', 'J18.5', 'J18.8', 'J18.1', 'J12.9', 'J13', 'J14', 'J15.0', 'J15.1', 'J15.2', 'J15.8', 'J15.9', 'J16.0', 'J16.8', 'J17.0', 'J17.1', 'J17.2', 'J17.8', 'J17.9'
    ) THEN d.icd_code END) AS comorbidity_count
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays i ON a.hadm_id = i.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
  GROUP BY p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag, i.stay_id
),
risk_scores AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY anchor_age + comorbidity_count + had_icu_stay) AS risk_quintile
  FROM pneumonia_patients
),
complications AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.risk_quintile,
    MAX(CASE WHEN d.icd_code IN (
      '410', '411', '412', '413', '414', '427', '428', '429', '427.31', '427.32', '427.4', '427.5', '427.6', '427.8', '427.9',
      'I21', 'I22', 'I23', 'I46', 'I47', 'I48', 'I49', 'I50'
    ) THEN 1 ELSE 0 END) AS has_cv_complication,
    MAX(CASE WHEN d.icd_code IN (
      '430', '431', '432', '433', '434', '435', '436', '437', '438', '780.3', '780.31', '780.32', '780.39', '781.0', '781.1', '781.2', '781.3', '781.4', '781.5', '781.6', '781.9',
      'G40', 'G41', 'G42', 'G43', 'G44', 'G45', 'G46', 'G47', 'G48', 'G50', 'G51', 'G52', 'G53', 'G54', 'G55', 'G56', 'G57', 'G58', 'G59', 'G60', 'G61', 'G62', 'G63', 'G64', 'G65', 'G66', 'G67', 'G68', 'G69', 'G70', 'G71', 'G72', 'G73', 'G74', 'G75', 'G76', 'G77', 'G78', 'G79', 'G80', 'G81', 'G82', 'G83', 'G84', 'G85', 'G86', 'G87', 'G88', 'G89', 'G90', 'G91', 'G92', 'G93', 'G94', 'G95', 'G96', 'G97', 'G98;