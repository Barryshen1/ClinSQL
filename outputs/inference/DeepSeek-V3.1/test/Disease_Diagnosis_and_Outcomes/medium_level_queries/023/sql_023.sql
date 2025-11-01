WITH stroke_patients AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Use MAX aggregation instead of window functions
    MAX(CASE 
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%') 
          OR (diag.icd_version = 9 AND (diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR diag.icd_code = '436'))
        THEN 1 ELSE 0 END) AS ischemic_flag,
    MAX(CASE 
        WHEN (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
          OR (diag.icd_version = 9 AND (diag.icd_code LIKE '430%' OR diag.icd_code LIKE '431%' OR diag.icd_code LIKE '432%'))
        THEN 1 ELSE 0 END) AS hemorrhagic_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
  GROUP BY p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  -- Filter for stroke patients after aggregation
  HAVING ischemic_flag = 1 OR hemorrhagic_flag = 1
),

stroke_types AS (
  SELECT 
    *,
    CASE 
      WHEN ischemic_flag = 1 AND hemorrhagic_flag = 0 THEN 'Ischemic'
      WHEN hemorrhagic_flag = 1 AND ischemic_flag = 0 THEN 'Hemorrhagic'
      ELSE 'Both' 
    END AS stroke_type
  FROM stroke_patients
),

comorbidities AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN (
        (icd_version = 10 AND icd_code LIKE 'N18%') OR
        (icd_version = 9 AND icd_code LIKE '585%')
      ) THEN 1 ELSE 0 END) AS ckd,
    MAX(CASE WHEN (
        (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%')) OR
        (icd_version = 9 AND icd_code LIKE '250%')
      ) THEN 1 ELSE 0 END) AS diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

comorbidity_burden AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE hadm_id IN (SELECT hadm_id FROM stroke_types)
  GROUP BY hadm_id
),

tertiles AS (
  SELECT 
    st.*,
    c.ckd,
    c.diabetes,
    cb.num_diagnoses,
    NTILE(3) OVER (PARTITION BY st.stroke_type ORDER BY cb.num_diagnoses) AS comorbidity_tertile
  FROM stroke_types st
  LEFT JOIN comorbidities c ON st.hadm_id = c.hadm_id
  LEFT JOIN comorbidity_burden cb ON st.hadm_id = cb.hadm_id
),

los_data AS (
  SELECT 
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM tertiles
),

-- Calculate median LOS per group
median_los_per_group AS (
  SELECT
    stroke_type,
    comorbidity_tertile,
    PERCENTILE_CONT(los, 0.5) OVER (PARTITION BY stroke_type, comorbidity_tertile) AS median_los
  FROM los_data
  GROUP BY stroke_type, comorbidity_tertile, los
),

-- Aggregate other metrics
aggregated_metrics AS (
  SELECT
    stroke_type,
    comorbidity_tertile,
    COUNT(*) AS num_admissions,
    ROUND(100 * AVG(hospital_expire_flag), 2) AS in_hospital_mortality_percent,
    ROUND(100 * AVG(ckd), 2) AS ckd_prevalence_percent,
    ROUND(100 * AVG(diabetes), 2) AS diabetes_prevalence_percent
  FROM los_data
  GROUP BY stroke_type, comorbidity_tertile
)

-- Join median LOS to aggregated results
SELECT
  a.stroke_type,
  a.comorbidity_tertile,
  a.num_admissions,
  a.in_hospital_mortality_percent,
  m.median_los,
  a.ckd_prevalence_percent,
  a.diabetes_prevalence_percent
FROM aggregated_metrics a
LEFT JOIN (
  SELECT DISTINCT stroke_type, comorbidity_tertile, median_los
  FROM median_los_per_group
) m
  ON a.stroke_type = m.stroke_type AND a.comorbidity_tertile = m.comorbidity_tertile
ORDER BY a.stroke_type, a.comorbidity_tertile;