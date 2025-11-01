WITH dka_icd_codes AS (
  -- ICD-9 and ICD-10 codes for DKA (refined for diabetic ketoacidosis)
  SELECT DISTINCT icd_code, icd_version 
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (LOWER(long_title) LIKE '%diabetic%ketoacidosis%' 
         OR icd_code IN ('E10.10', 'E10.11', 'E13.10', 'E13.11', 'E14.10', 'E14.11', 
                         '250.10', '250.11', '250.12', '250.13'))
),

base_admissions AS (
  -- All male, age 59-69 admissions
  SELECT 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    p.gender, p.anchor_age,
    -- Simple risk score: age adjustment + num secondary dx + AKI/ARDS flags (computed later)
    (p.anchor_age - 50) AS age_score,
    -- LOS for survivors
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.hospital_expire_flag = 0  -- Exclude immediate deaths for LOS calc, but mortality uses dod
),

dka_cohort AS (
  SELECT 
    ba.*,
    p.dod,
    -- Num secondary diagnoses
    COUNTIF(di.seq_num > 1) AS num_secondary_dx,
    -- AKI flag (ICD N17.* for ICD-10; 584.*, 585.* for ICD-9)
    LOGICAL_OR(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'N17%' THEN TRUE 
                    WHEN di.icd_version = 9 AND di.icd_code LIKE '58[45]%' THEN TRUE 
               END) AS has_aki,
    -- ARDS flag (ICD J80 or J96.0* for ICD-10; 518.5, 518.81, 518.82 for ICD-9)
    LOGICAL_OR(CASE WHEN di.icd_version = 10 AND (di.icd_code = 'J80' OR di.icd_code LIKE 'J96.0%') THEN TRUE
                    WHEN di.icd_version = 9 AND di.icd_code IN ('518.5', '518.81', '518.82') THEN TRUE 
               END) AS has_ards,
    -- 30-day mortality (using dod for post-discharge)
    CASE WHEN p.dod IS NOT NULL 
         AND DATE_DIFF(p.dod, ba.admittime, DAY) <= 30 
         AND p.dod >= ba.admittime THEN 1.0 ELSE 0.0 END AS mortality_30d,
    -- DKA flag
    LOGICAL_OR(dic.icd_code IS NOT NULL) AS is_dka
  FROM base_admissions ba
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ba.hadm_id = di.hadm_id
  LEFT JOIN dka_icd_codes dic
    ON di.icd_code = dic.icd_code 
    AND CAST(di.icd_version AS STRING) = CAST(dic.icd_version AS STRING)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ba.subject_id = p.subject_id
  GROUP BY 
    ba.subject_id, ba.hadm_id, ba.admittime, ba.dischtime, ba.hospital_expire_flag,
    ba.gender, ba.anchor_age, ba.age_score, ba.hosp_los, p.dod
  HAVING is_dka = TRUE  -- DKA cohort
),

general_cohort AS (
  -- Same as above but exclude DKA
  SELECT 
    ba.*,
    p.dod,
    COUNTIF(di.seq_num > 1) AS num_secondary_dx,
    LOGICAL_OR(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'N17%' THEN TRUE 
                    WHEN di.icd_version = 9 AND di.icd_code LIKE '58[45]%' THEN TRUE 
               END) AS has_aki,
    LOGICAL_OR(CASE WHEN di.icd_version = 10 AND (di.icd_code = 'J80' OR di.icd_code LIKE 'J96.0%') THEN TRUE
                    WHEN di.icd_version = 9 AND di.icd_code IN ('518.5', '518.81', '518.82') THEN TRUE 
               END) AS has_ards,
    CASE WHEN p.dod IS NOT NULL 
         AND DATE_DIFF(p.dod, ba.admittime, DAY) <= 30 
         AND p.dod >= ba.admittime THEN 1.0 ELSE 0.0 END AS mortality_30d,
    LOGICAL_OR(dic.icd_code IS NOT NULL) AS is_dka
  FROM base_admissions ba
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ba.hadm_id = di.hadm_id
  LEFT JOIN dka_icd_codes dic
    ON di.icd_code = dic.icd_code 
    AND CAST(di.icd_version AS STRING) = CAST(dic.icd_version AS STRING)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ba.subject_id = p.subject_id
  GROUP BY 
    ba.subject_id, ba.hadm_id, ba.admittime, ba.dischtime, ba.hospital_expire_flag,
    ba.gender, ba.anchor_age, ba.age_score, ba.hosp_los, p.dod
  HAVING is_dka = FALSE  -- General cohort (age-matched inpatients without DKA)
),

-- Risk score: age_score + num_secondary_dx + AKI (1/0) + ARDS (1/0)
dka_metrics AS (
  SELECT 
    'DKA' AS cohort,
    COUNT(*) AS n_patients,
    AVG(age_score + num_secondary_dx + IF(has_aki, 1, 0) + IF(has_ards, 1, 0)) AS mean_risk_score,
    AVG(mortality_30d) AS mortality_rate,
    AVG(IF(has_aki, 1.0, 0.0)) AS aki_rate,
    AVG(IF(has_ards, 1.0, 0.0)) AS ards_rate,
    AVG(IF(hospital_expire_flag = 0, hosp_los, NULL)) AS mean_los_survivors
  FROM dka_cohort
),

general_metrics AS (
  SELECT 
    'General' AS cohort,
    COUNT(*) AS n_patients,
    AVG(age_score + num_secondary_dx + IF(has_aki, 1, 0) + IF(has_ards, 1, 0)) AS mean_risk_score,
    AVG(mortality_30d) AS mortality_rate,
    AVG(IF(has_aki, 1.0, 0.0)) AS aki_rate,
    AVG(IF(has_ards, 1.0, 0.0)) AS ards_rate,
    AVG(IF(hospital_expire_flag = 0, hosp_los, NULL)) AS mean_los_survivors
  FROM general_cohort
),

-- Percentile: Where DKA mean risk falls in general risk distribution
risk_distribution AS (
  SELECT 
    age_score + num_secondary_dx + IF(has_aki, 1, 0) + IF(has_ards, 1, 0) AS risk_score,
    PERCENT_RANK() OVER (ORDER BY age_score + num_secondary_dx + IF(has_aki, 1, 0) + IF(has_ards, 1, 0)) AS risk_percentile
  FROM general_cohort
)

SELECT 
  dm.*,
  gm.aki_rate AS general_aki_rate,
  gm.ards_rate AS general_ards_rate,
  gm.mean_los_survivors AS general_los_survivors,
  -- Approximate percentile for DKA mean risk in general distribution
  (SELECT AVG(risk_percentile) FROM risk_distribution WHERE risk_score <= dm.mean_risk_score) * 100 AS dka_risk_percentile_in_general
FROM dka_metrics dm
CROSS JOIN general_metrics gm;