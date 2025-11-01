WITH 
  charlson_mapping AS (
    SELECT 'I25.1' AS icd10_code, 1 AS weight
    UNION ALL SELECT 'I50.9', 1
    UNION ALL SELECT 'I25.10', 1
    UNION ALL SELECT 'I25.11', 1
    UNION ALL SELECT 'I25.12', 1
    UNION ALL SELECT 'I25.19', 1
    UNION ALL SELECT 'I50.1', 1
    UNION ALL SELECT 'I50.2', 1
    UNION ALL SELECT 'I50.3', 1
    UNION ALL SELECT 'I50.4', 1
    UNION ALL SELECT 'I50.81', 1
    UNION ALL SELECT 'I50.89', 1
    UNION ALL SELECT 'I50.9', 1
    UNION ALL SELECT 'C34', 2  -- Lung cancer
    UNION ALL SELECT 'C38.1', 2  -- Melanoma
    UNION ALL SELECT 'C61', 2  -- Kidney cancer
    UNION ALL SELECT 'C81', 2  -- Lymphoma
    UNION ALL SELECT 'C82', 2  -- Leukemia
    UNION ALL SELECT 'C83', 2  -- Other hematopoietic malignancy
    UNION ALL SELECT 'C84', 2  -- Multiple myeloma
    UNION ALL SELECT 'C85', 2  -- Other plasma cell malignancy
    UNION ALL SELECT 'C88', 2  -- Secondary malignancy
    UNION ALL SELECT 'C96.8', 2  -- Neoplasm of unspecified behavior
    UNION ALL SELECT 'I80', 1  -- Peripheral vascular disease
    UNION ALL SELECT 'I63.9', 1  -- Cerebrovascular disease
    UNION ALL SELECT 'G31.0', 1  -- Dementia
    UNION ALL SELECT 'J44.9', 1  -- Chronic pulmonary disease
    UNION ALL SELECT 'M32', 1  -- Rheumatic disease
    UNION ALL SELECT 'K25.9', 1  -- Peptic ulcer disease
    UNION ALL SELECT 'K70.9', 1  -- Mild liver disease
    UNION ALL SELECT 'E11', 1  -- Diabetes without complications
    UNION ALL SELECT 'E11.2', 2  -- Diabetes with complications
    UNION ALL SELECT 'G81.9', 2  -- Hemiplegia or paraplegia
    UNION ALL SELECT 'N18.9', 2  -- Renal disease
    UNION ALL SELECT 'K72.9', 3  -- Moderate or severe liver disease
    UNION ALL SELECT 'C79', 6  -- Metastatic solid tumor
    UNION ALL SELECT 'B20', 6  -- AIDS
  ),
  eligible_patients AS (
    SELECT subject_id, gender, anchor_age, anchor_year, dod
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 70 AND 80
  ),
  pe_codes AS (
    SELECT DISTINCT d.subject_id, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN eligible_patients e ON d.subject_id = e.subject_id
    WHERE d.icd_version = 10
      AND d.icd_code IN ('I26.90', 'I26.91', 'I26.92', 'I26.99') -- Pulmonary embolism codes
  ),
  admissions_with_details AS (
    SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN pe_codes pe ON a.hadm_id = pe.hadm_id
  ),
  mortality_90d AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      a.admittime,
      IF(p.dod IS NOT NULL AND p.dod <= a.admittime + INTERVAL 90 DAY, 1, 0) AS died_90d
    FROM admissions_with_details a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  ),
  cci_calculation AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      COALESCE(SUM(c.weight), 0) AS cci
    FROM admissions_with_details a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id AND d.icd_version = 10
    LEFT JOIN charlson_mapping c ON d.icd_code = c.icd10_code
    GROUP BY a.subject_id, a.hadm_id
  ),
  cci_quintiles AS (
    SELECT 
      subject_id,
      hadm_id,
      cci,
      NTILE(5) OVER (ORDER BY cci) AS quintile
    FROM cci_calculation
  ),
  general_mortality AS (
    SELECT 
      IF(p.dod IS NOT NULL AND p.dod <= a.admittime + INTERVAL 90 DAY, 1, 0) AS died_90d
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 70 AND 80
  ),
  general_mortality_rate AS (
    SELECT AVG(died_90d) AS general_mortality_90d
    FROM general_mortality
  ),
  aki_rates AS (
    SELECT 
      q.quintile,
      COUNT(DISTINCT CASE WHEN d.icd_code = 'N17.9' THEN q.hadm_id END) * 1.0 / COUNT(DISTINCT q.hadm_id) AS aki_rate
    FROM cci_quintiles q
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON q.subject_id = d.subject_id AND q.hadm_id = d.hadm_id AND d.icd_version = 10
    GROUP BY q.quintile
  ),
  ards_rates AS (
    SELECT 
      q.quintile,
      COUNT(DISTINCT CASE WHEN d.icd_code = 'J80' THEN q.hadm_id END) * 1.0 / COUNT(DISTINCT q.hadm_id) AS ards_rate
    FROM cci_quintiles q
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON q.subject_id = d.subject_id AND q.hadm_id = d.hadm_id AND d.icd_version = 10
    GROUP BY q.quintile
  ),
  survivor_los AS (
    SELECT 
      q.quintile,
      APPROX_QUANTILES(EXTRACT(DAY FROM (a.dischtime - a.admittime)), 100)[OFFSET(50)] AS median_los
    FROM cci_quintiles q
    JOIN admissions_with_details a ON q.hadm_id = a.hadm_id
    WHERE a.hospital_expire_flag = 0 -- survivors
    GROUP BY q.quintile
  ),
  quintile_metrics AS (
    SELECT 
      q.quintile,
      COUNT(*) AS num_patients,
      AVG(m.died_90d) AS mortality_90d,
      (SELECT general_mortality_90d FROM general_mortality_rate) AS general_90d_mortality,
      aki.aki_rate,
      ards.ards_rate,
      sl.median_los
    FROM cci_quintiles q
    JOIN mortality_90d m ON q.hadm_id = m.hadm_id
    LEFT JOIN aki_rates aki ON q.quintile = aki.quintile
    LEFT JOIN ards_rates ards ON q.quintile = ards.quintile
    LEFT JOIN survivor_los sl ON q.quintile = sl.quintile
    GROUP BY q.quintile, aki.aki_rate, ards.ards_rate, sl.median_los, (SELECT general_mortality_90d FROM general_mortality_rate)
  )
SELECT * FROM quintile_metrics
ORDER BY quintile;