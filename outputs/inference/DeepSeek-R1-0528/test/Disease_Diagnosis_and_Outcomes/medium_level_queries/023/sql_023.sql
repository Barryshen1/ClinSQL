WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    pat.anchor_age, 
    pat.anchor_year,
    pat.gender,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    -- Filter age 52-62 at admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 52 AND 62
),

stroke_admissions AS (
  SELECT 
    diag.hadm_id,
    MAX(CASE 
          WHEN (diag.icd_version = 9 AND (diag.icd_code LIKE '433%1' OR diag.icd_code LIKE '434%1' OR diag.icd_code = '436'))
             OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I63%' OR diag.icd_code = 'I67.89')) 
          THEN 1 ELSE 0 
        END) AS is_ischemic,
    MAX(CASE 
          WHEN (diag.icd_version = 9 AND (diag.icd_code IN ('430','431') OR diag.icd_code LIKE '432%'))
             OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%')) 
          THEN 1 ELSE 0 
        END) AS is_hemorrhagic
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  GROUP BY diag.hadm_id
  HAVING 
    (MAX(is_ischemic) = 1 AND MAX(is_hemorrhagic) = 0) OR  -- Ischemic only
    (MAX(is_hemorrhagic) = 1 AND MAX(is_ischemic) = 0)     -- Hemorrhagic only
),

charlson_map AS (
  -- Simplified CCI mapping (expand with full codes in practice)
  SELECT * 
  FROM UNNEST([
    -- Myocardial Infarction
    STRUCT('410' AS icd9_code, 'I21' AS icd10_code, 1 AS weight, 'MI' AS category),
    STRUCT('410' AS icd9_code, 'I22' AS icd10_code, 1, 'MI'),
    STRUCT('412' AS icd9_code, 'I25' AS icd10_code, 1, 'MI'),
    -- Congestive Heart Failure
    STRUCT('428' AS icd9_code, 'I50' AS icd10_code, 1, 'CHF'),
    -- Peripheral Vascular Disease
    STRUCT('441' AS icd9_code, 'I71' AS icd10_code, 1, 'PVD'),
    -- Dementia (excluded Cerebrovascular)
    STRUCT('290' AS icd9_code, 'F00' AS icd10_code, 1, 'DEMENTIA'),
    -- Chronic Pulmonary Disease
    STRUCT('491' AS icd9_code, 'J42' AS icd10_code, 1, 'CPD'),
    -- Rheumatologic Disease
    STRUCT('710' AS icd9_code, 'M32' AS icd10_code, 1, 'RHEUM'),
    -- Peptic Ulcer Disease
    STRUCT('531' AS icd9_code, 'K25' AS icd10_code, 1, 'PUD'),
    -- Mild Liver Disease
    STRUCT('571' AS icd9_code, 'K70' AS icd10_code, 1, 'MILD_LIVER'),
    -- Diabetes without complication
    STRUCT('2500' AS icd9_code, 'E10' AS icd10_code, 1, 'DIABETES'),
    STRUCT('2501' AS icd9_code, 'E11' AS icd10_code, 1, 'DIABETES'),
    -- Diabetes with complication
    STRUCT('2502' AS icd9_code, 'E12' AS icd10_code, 2, 'DIABETES_CC'),
    STRUCT('2503' AS icd9_code, 'E13' AS icd10_code, 2, 'DIABETES_CC'),
    -- Renal Disease (CKD)
    STRUCT('585' AS icd9_code, 'N18' AS icd10_code, 2, 'RENAL'),
    -- Any Malignancy
    STRUCT('140' AS icd9_code, 'C0' AS icd10_code, 2, 'MALIGNANCY'),
    -- Moderate/Severe Liver Disease
    STRUCT('572' AS icd9_code, 'K72' AS icd10_code, 3, 'SEVERE_LIVER'),
    -- Metastatic Solid Tumor
    STRUCT('196' AS icd9_code, 'C77' AS icd10_code, 6, 'METASTASIS'),
    -- AIDS/HIV
    STRUCT('042' AS icd9_code, 'B20' AS icd10_code, 6, 'HIV')
  ])
),

charlson_scored AS (
  SELECT 
    hadm_id,
    COALESCE(SUM(weight), 0) AS charlson_score,
    MAX(CASE WHEN category = 'RENAL' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN category IN ('DIABETES','DIABETES_CC') THEN 1 ELSE 0 END) AS has_diabetes
  FROM (
    SELECT DISTINCT
      diag.hadm_id,
      cm.category,
      cm.weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    LEFT JOIN charlson_map cm
      ON (diag.icd_version = 9 AND diag.icd_code LIKE CONCAT(cm.icd9_code, '%'))
         OR (diag.icd_version = 10 AND diag.icd_code LIKE CONCAT(cm.icd10_code, '%'))
    WHERE diag.seq_num > 1  -- Secondary diagnoses only
  ) comorb_categories
  GROUP BY hadm_id
),

combined AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.age_admit,
    c.los,
    c.hospital_expire_flag,
    CASE 
      WHEN s.is_ischemic = 1 THEN 'Ischemic'
      WHEN s.is_hemorrhagic = 1 THEN 'Hemorrhagic'
    END AS stroke_type,
    COALESCE(cs.charlson_score, 0) AS charlson_score,  -- Handle missing comorbidities
    COALESCE(cs.has_ckd, 0) AS has_ckd,
    COALESCE(cs.has_diabetes, 0) AS has_diabetes,
    -- Split CCI into tertiles (1=low, 2=medium, 3=high)
    NTILE(3) OVER (ORDER BY COALESCE(cs.charlson_score, 0)) AS comorbidity_tertile
  FROM cohort c
  INNER JOIN stroke_admissions s 
    ON c.hadm_id = s.hadm_id
  LEFT JOIN charlson_scored cs 
    ON c.hadm_id = cs.hadm_id
)

SELECT 
  stroke_type,
  comorbidity_tertile,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  COUNTIF(los < 8) * 100.0 / COUNT(*) AS los_lt_8_pct,
  COUNTIF(los >= 8) * 100.0 / COUNT(*) AS los_gte_8_pct,
  AVG(has_ckd) * 100 AS ckd_rate,
  AVG(has_diabetes) * 100 AS diabetes_rate
FROM combined
GROUP BY stroke_type, comorbidity_tertile
ORDER BY stroke_type, comorbidity_tertile;