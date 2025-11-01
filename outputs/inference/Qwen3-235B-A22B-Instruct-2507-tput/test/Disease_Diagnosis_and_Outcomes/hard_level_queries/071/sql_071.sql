with ICU stay
-- Compare risk score, mortality, complications, and LOS vs age-matched controls
WITH age_comorb AS (
  SELECT
    pat.subject_id,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year,
    pat.dod,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    -- Compute age at admission
    (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS age_at_admit,
    -- ICU stay flag
    MAX(CASE WHEN ics.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_icu_stay
  FROM `physionet-data.mimiciv_3_1_hosp`.patients pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON pat.subject_id = adm.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays ics
    ON adm.hadm_id = ics.hadm_id
  GROUP BY pat.subject_id, pat.gender, pat.anchor_age, pat.anchor_year, pat.dod,
           adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
),
filtered_cohort AS (
  SELECT *
  FROM age_comorb
  WHERE gender = 'F'
    AND age_at_admit BETWEEN 68 AND 78
    AND had_icu_stay = 1
),
-- Get all diagnoses for these admissions
diagnoses AS (
  SELECT
    dc.hadm_id,
    dc.icd_code,
    dc.icd_version,
    dicd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dicd
    ON dc.icd_code = dicd.icd_code AND dc.icd_version = dicd.icd_version
  WHERE dc.hadm_id IN (SELECT hadm_id FROM filtered_cohort)
),
-- Define AMI: ICD-9: 410, ICD-10: I21, I22
ami_cohort AS (
  SELECT DISTINCT hadm_id
  FROM diagnoses
  WHERE (icd_version = 9 AND icd_code LIKE '410%')
     OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
),
-- Charlson Comorbidity Index (CCI) calculation
charlson_components AS (
  SELECT
    d.hadm_id,
    -- Myocardial infarction
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') 
              OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%') THEN 1 ELSE 0 END) AS mi,
    -- Congestive heart failure
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('428')) 
              OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1 ELSE 0 END) AS chf,
    -- Peripheral vascular disease
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('440','441')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'I70%' OR d.icd_code LIKE 'I71%')) THEN 1 ELSE 0 END) AS pvd,
    -- Cerebrovascular disease
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('430','431','432','433','434','435','436','437','438')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%' OR d.icd_code LIKE 'I65%' OR d.icd_code LIKE 'I66%' OR d.icd_code LIKE 'I67%' OR d.icd_code LIKE 'I68%' OR d.icd_code LIKE 'I69%')) THEN 1 ELSE 0 END) AS cerebrovascular,
    -- Dementia
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('290','294.1','331.2')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'F00%' OR d.icd_code LIKE 'F01%' OR d.icd_code LIKE 'F02%' OR d.icd_code LIKE 'F03%' OR d.icd_code LIKE 'G30%')) THEN 1 ELSE 0 END) AS dementia,
    -- Chronic pulmonary disease
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('490','491','492','493','494','495','496')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'J40%' OR d.icd_code LIKE 'J41%' OR d.icd_code LIKE 'J42%' OR d.icd_code LIKE 'J43%' OR d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J45%' OR d.icd_code LIKE 'J46%' OR d.icd_code LIKE 'J47%')) THEN 1 ELSE 0 END) AS copd,
    -- Connective tissue disease
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('710','714')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'M30%' OR d.icd_code LIKE 'M31%' OR d.icd_code LIKE 'M32%' OR d.icd_code LIKE 'M33%' OR d.icd_code LIKE 'M34%' OR d.icd_code LIKE 'M35%')) THEN 1 ELSE 0 END) AS ctd,
    -- Peptic ulcer disease
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('531','532','533','534')) 
              OR (d.icd_version = 10 AND d.icd_code LIKE 'K25%' OR d.icd_code LIKE 'K26%' OR d.icd_code LIKE 'K27%' OR d.icd_code LIKE 'K28%') THEN 1 ELSE 0 END) AS pud,
    -- Mild liver disease
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('570','571')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'B18%' OR d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K71%' OR d.icd_code LIKE 'K73%' OR d.icd_code LIKE 'K74%' OR d.icd_code LIKE 'K76%')) THEN 1 ELSE 0 END) AS mild_liver,;