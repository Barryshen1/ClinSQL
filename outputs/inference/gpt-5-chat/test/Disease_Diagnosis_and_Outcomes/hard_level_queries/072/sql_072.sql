WITH acs_codes AS (
  SELECT 'ICD9' AS type, code
  FROM UNNEST([
    '410', -- AMI
    '4100','4101','4102','4103','4104','4105','4106','4107','4108','4109', 
    '4111' -- Unstable angina
  ]) AS code
  UNION ALL
  SELECT 'ICD10', code
  FROM UNNEST([
    'I200','I21','I210','I211','I212','I213','I214','I219','I21A1','I21A9','I22', 'I220','I221','I222','I228','I229'
  ]) AS code
),
cardiac_comp_codes AS (
  SELECT 'ICD9' AS type, code
  FROM UNNEST([
    '4275', '42741','428','4280','4281','4289' -- arrhythmia, CHF
  ]) AS code
  UNION ALL
  SELECT 'ICD10', code
  FROM UNNEST([
    'I46','I470','I471','I472','I479','I48','I489','I500','I509'
  ]) AS code
),
neuro_comp_codes AS (
  SELECT 'ICD9' AS type, code
  FROM UNNEST([
    '434','4340','4341','4349','G459'
  ]) AS code
  UNION ALL
  SELECT 'ICD10', code
  FROM UNNEST([
    'I63','I639','I64','G40','G409','G401'
  ]) AS code
),
adm_with_demo AS (
  SELECT a.subject_id, a.hadm_id, p.gender, p.anchor_age,
         a.admittime, a.dischtime, p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
icu_adms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
dx AS (
  SELECT di.subject_id, di.hadm_id, di.icd_code, di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
),
acs_flag AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM dx d
  JOIN acs_codes ac
    ON (d.icd_version = 9 AND ac.type='ICD9' AND REGEXP_CONTAINS(d.icd_code, CONCAT('^', ac.code)))
    OR (d.icd_version = 10 AND ac.type='ICD10' AND REGEXP_CONTAINS(d.icd_code, CONCAT('^', ac.code)))
),
cardiac_comp_flag AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM dx d
  JOIN cardiac_comp_codes cc
    ON (d.icd_version = 9 AND cc.type='ICD9' AND REGEXP_CONTAINS(d.icd_code, CONCAT('^', cc.code)))
    OR (d.icd_version = 10 AND cc.type='ICD10' AND REGEXP_CONTAINS(d.icd_code, CONCAT('^', cc.code)))
),
neuro_comp_flag AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM dx d
  JOIN neuro_comp_codes nc
    ON (d.icd_version = 9 AND nc.type='ICD9' AND REGEXP_CONTAINS(d.icd_code, CONCAT('^', nc.code)))
    OR (d.icd_version = 10 AND nc.type='ICD10' AND REGEXP_CONTAINS(d.icd_code, CONCAT('^', nc.code)))
),
cohort AS (
  SELECT ad.subject_id, ad.hadm_id, ad.gender, ad.anchor_age,
         ad.admittime, ad.dischtime, ad.dod,
         CASE WHEN acs.subject_id IS NOT NULL THEN 1 ELSE 0 END AS acs,
         CASE WHEN cc.subject_id IS NOT NULL THEN 1 ELSE 0 END AS cardiac_comp,
         CASE WHEN nc.subject_id IS NOT NULL THEN 1 ELSE 0 END AS neuro_comp
  FROM adm_with_demo ad
  JOIN icu_adms iu
    ON ad.hadm_id = iu.hadm_id
  LEFT JOIN acs_flag acs
    ON ad.hadm_id = acs.hadm_id
  LEFT JOIN cardiac_comp_flag cc
    ON ad.hadm_id = cc.hadm_id
  LEFT JOIN neuro_comp_flag nc
    ON ad.hadm_id = nc.hadm_id
  WHERE ad.anchor_age BETWEEN 67 AND 77
    AND ad.gender = 'F'
),
metrics AS (
  SELECT 
    CASE WHEN acs=1 THEN 'ACS' ELSE 'General' END AS cohort_group,
    COUNT(*) AS n_admissions,
    AVG( NULL ) AS mean_risk_score,  -- placeholder: replace with actual computation if available
    AVG(CASE WHEN dod IS NOT NULL AND DATETIME_DIFF(dod, dischtime, DAY) <= 30 AND DATETIME_DIFF(dod, dischtime, DAY) >= 0 THEN 1 ELSE 0 END) AS mortality_30d_rate,
    AVG(cardiac_comp) AS cardiac_comp_rate,
    AVG(neuro_comp) AS neuro_comp_rate,
    AVG(CASE WHEN (dod IS NULL OR DATETIME_DIFF(dod, dischtime, DAY) > 30) THEN DATETIME_DIFF(dischtime, admittime, DAY) ELSE NULL END) AS mean_los_survivors
  FROM cohort
  GROUP BY cohort_group
),
percentile_calc AS (
  SELECT cohort_group, mortality_30d_rate,
         PERCENT_RANK() OVER (ORDER BY mortality_30d_rate) AS mortality_rate_percentile
  FROM metrics
)
SELECT m.*, p.mortality_rate_percentile
FROM metrics m
LEFT JOIN percentile_calc p
  ON m.cohort_group = p.cohort_group
ORDER BY cohort_group;