WITH stroke_icds AS (
  -- List of ICD codes for stroke
  SELECT DISTINCT icd_code, icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'(stroke|cerebral infarction|intracerebral hemorrhage|cerebrovascular accident)')
     OR icd_code IN (
      -- Common stroke codes
      'I63', 'I63.0', 'I63.1', 'I63.2', 'I63.3', 'I63.4', 'I63.5', 'I63.6', 'I63.8', 'I63.9', -- Ischemic stroke ICD-10
      'I61', 'I61.0', 'I61.1', 'I61.2', 'I61.3', 'I61.4', 'I61.5', 'I61.6', 'I61.8', 'I61.9', -- Hemorrhagic stroke ICD-10
      '434', '434.0', '434.1', '434.9', '433', '433.0', '433.1', '433.9', '436', '431' -- ICD-9
     )
),
ckd_icds AS (
  SELECT DISTINCT icd_code, icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'(chronic kidney disease|ckd)')
     OR icd_code LIKE 'N18%' -- ICD-10 CKD
     OR icd_code LIKE '585%' -- ICD-9 CKD
),
diabetes_icds AS (
  SELECT DISTINCT icd_code, icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'diabetes')
     OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%' -- ICD-10
     OR icd_code LIKE '250%' -- ICD-9
),
elixhauser_map AS (
  -- Simplified: map ICD codes to Elixhauser comorbidity categories
  SELECT DISTINCT icd_code, icd_version, 
    CASE
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(congestive heart failure)') THEN 'CHF'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(cardiac arrhythmias)') THEN 'Arrhythmia'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(valvular disease)') THEN 'Valvular'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(pulmonary circulation disorders)') THEN 'Pulmonary'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(peripheral vascular disorders)') THEN 'Peripheral'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(hypertension)') THEN 'Hypertension'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(paralysis)') THEN 'Paralysis'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(other neurological disorders)') THEN 'Neuro'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(chronic pulmonary disease)') THEN 'COPD'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(diabetes)') THEN 'Diabetes'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(renal failure|chronic kidney disease|ckd)') THEN 'Renal'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(liver disease)') THEN 'Liver'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(peptic ulcer disease)') THEN 'Ulcer'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(aids|hiv)') THEN 'AIDS'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(lymphoma)') THEN 'Lymphoma'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(metastatic cancer)') THEN 'Metastatic Cancer'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(solid tumor)') THEN 'Solid Tumor'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(rheumatoid arthritis|collagen vascular diseases)') THEN 'RA/CVD'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(coagulopathy)') THEN 'Coagulopathy'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(obesity)') THEN 'Obesity'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(weight loss)') THEN 'Weight Loss'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(fluid and electrolyte disorders)') THEN 'Fluid/Electrolyte'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(blood loss anemia)') THEN 'Blood Loss Anemia'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(deficiency anemia)') THEN 'Deficiency Anemia'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(alcohol abuse)') THEN 'Alcohol'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(drug abuse)') THEN 'Drug'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(psychoses)') THEN 'Psychoses'
      WHEN REGEXP_CONTAINS(LOWER(long_title), r'(depression)') THEN 'Depression'
      ELSE NULL
    END AS elixhauser_cat
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE TRUE
),
stroke_admissions AS (
  -- Get admissions for males 52-62 with stroke diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON adm.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  JOIN stroke_icds s
    ON diag.icd_code = s.icd_code AND diag.icd_version = s.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
),
admission_comorbidities AS (
  -- For each admission, count unique Elixhauser comorbidity categories
  SELECT
    adm.subject_id,
    adm.hadm_id,
    COUNT(DISTINCT em.elixhauser_cat) AS comorbidity_count,
    MAX(CASE WHEN ckd.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN diab.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_diabetes
  FROM stroke_admissions adm
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  LEFT JOIN elixhauser_map em
    ON diag.icd_code = em.icd_code AND diag.icd_version = em.icd_version
  LEFT JOIN ckd_icds ckd
    ON diag.icd_code = ckd.icd_code AND diag.icd_version = ckd.icd_version
  LEFT JOIN diabetes_icds diab
    ON diag.icd_code = diab.icd_code AND diag.icd_version = diab.icd_version
  GROUP BY adm.subject_id, adm.hadm_id
),
admission_features AS (
  -- Add ICU status, LOS, LOS category, comorbidity tertile
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.anchor_age,
    adm.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    com.comorbidity_count,
    com.has_ckd,
    com.has_diabetes,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) <= 5 THEN '<=5' ELSE '>5' END AS los_category
  FROM stroke_admissions adm
  LEFT JOIN admission_comorbidities com
    ON adm.hadm_id = com.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays icu
    ON adm.hadm_id = icu.hadm_id
),
admission_with_tertile AS (
  -- Assign comorbidity tertile within cohort
  SELECT *,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS comorbidity_tertile
  FROM admission_features
)
SELECT
  icu_status,
  los_category,
  comorbidity_tertile,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS mortality_percent,
  ROUND(100.0 * SUM(has_ckd) / COUNT(*), 1) AS ckd_percent,
  ROUND(100.0 * SUM(has_diabetes) / COUNT(*), 1) AS diabetes_percent
FROM admission_with_tertile
GROUP BY icu_status, los_category, comorbidity_tertile
ORDER BY icu_status, los_category, comorbidity_tertile;