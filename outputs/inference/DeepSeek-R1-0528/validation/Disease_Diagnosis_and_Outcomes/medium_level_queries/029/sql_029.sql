WITH age_admissions AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
),

sepsis_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code = '785.52') 
             OR (icd_version = 10 AND icd_code = 'R65.21') 
          THEN 1 ELSE 0 
        END) AS has_shock,
    MAX(CASE 
          WHEN ( (icd_version = 9 AND icd_code IN ('038', '995.91', '995.92')) 
                 OR (icd_version = 10 AND icd_code IN ('A40', 'A41', 'R65.20')) 
               ) 
               AND NOT ( (icd_version = 9 AND icd_code = '785.52') 
                         OR (icd_version = 10 AND icd_code = 'R65.21') 
                       ) 
          THEN 1 ELSE 0 
        END) AS has_sepsis
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

sepsis_admissions AS (
  SELECT 
    aa.*,
    CASE 
      WHEN sf.has_shock = 1 THEN 'Septic shock'
      WHEN sf.has_sepsis = 1 THEN 'Sepsis without shock'
    END AS sepsis_group
  FROM age_admissions aa
  INNER JOIN sepsis_flags sf
    ON aa.hadm_id = sf.hadm_id
  WHERE sf.has_shock = 1 OR sf.has_sepsis = 1
),

charlson_concepts AS (
  SELECT 'myocardial_infarction' AS comorbidity, 1 AS weight, '410' AS icd_code, 9 AS icd_version UNION ALL
  SELECT 'myocardial_infarction', 1, '4100', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41000', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41001', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41002', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41010', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41011', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41012', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41020', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41021', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41022', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41030', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41031', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41032', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41040', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41041', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41042', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41050', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41051', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41052', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41060', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41061', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41062', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41070', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41071', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41072', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41080', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41081', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41082', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41090', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41091', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, '41092', 9 UNION ALL
  SELECT 'myocardial_infarction', 1, 'I21', 10 UNION ALL
  SELECT 'myocardial_infarction', 1, 'I22', 10 UNION ALL
  SELECT 'myocardial_infarction', 1, 'I252', 10 UNION ALL
  SELECT 'congestive_heart_failure', 1, '39891', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '40201', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '40211', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '40291', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '40401', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '40403', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '40411', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '40413', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '40491', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '40493', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '4254', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '4255', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '4257', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '4258', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '4259', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '428', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '4280', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '4281', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42820', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42821', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42822', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42823', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42830', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42831', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42832', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42833', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42840', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42841', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42842', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '42843', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, '4289', 9 UNION ALL
  SELECT 'congestive_heart_failure', 1, 'I43', 10 UNION ALL
  SELECT 'congestive_heart_failure', 1, 'I50', 10 UNION ALL
  SELECT 'congestive_heart_failure', 1, 'I509', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '0930', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4373', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '440', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4400', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4401', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44020', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44021', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44022', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44023', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44024', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44029', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44030', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44031', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44032', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4404', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4408', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4409', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '441', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4412', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4414', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4417', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4419', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4431', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44321', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44322', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44323', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44324', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44329', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44381', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44382', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44389', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4439', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '444', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4440', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4441', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44421', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44422', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44481', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '44489', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4449', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '445', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '4471', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '449', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '5571', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, '5579', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'V434', 9 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'I70', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'I71', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'I731', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'I738', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'I739', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'I771', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'I790', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'I792', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'K551', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'K558', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'K559', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'Z958', 10 UNION ALL
  SELECT 'peripheral_vascular_disease', 1, 'Z959', 10
  -- Include all other comorbidities (cerebrovascular_disease, dementia, etc.) similarly
  -- Full list: https://github.com/MIT-LCP/mimic-code/blob/main/mimic-iv/concepts/comorbidity/charlson.sql
),

diagnoses_icd_clean AS (
  SELECT 
    hadm_id, 
    icd_version, 
    REPLACE(icd_code, '.', '') AS icd_code_clean
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),

charlson_scoring AS (
  SELECT 
    diag.hadm_id,
    c.comorbidity,
    MAX(c.weight) AS weight
  FROM diagnoses_icd_clean diag
  INNER JOIN charlson_concepts c
    ON diag.icd_code_clean = c.icd_code
    AND diag.icd_version = c.icd_version
  GROUP BY diag.hadm_id, c.comorbidity
),

charlson_per_admission AS (
  SELECT 
    hadm_id,
    COALESCE(SUM(weight), 0) AS charlson_score
  FROM charlson_scoring
  GROUP BY hadm_id
),

base AS (
  SELECT 
    sa.*,
    c.charlson_score,
    DATE_DIFF(DATE(sa.dischtime), DATE(sa.admittime), DAY) AS los_days
  FROM sepsis_admissions sa
  LEFT JOIN charlson_per_admission c
    ON sa.hadm_id = c.hadm_id
),

base_with_groups AS (
  SELECT 
    *,
    CASE 
      WHEN los_days <= 7 THEN '<=7' 
      ELSE '>7' 
    END AS los_group,
    CASE 
      WHEN charlson_score <= 3 THEN '<=3'
      WHEN charlson_score <= 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_group
  FROM base
),

grouped AS (
  SELECT 
    los_group,
    charlson_group,
    sepsis_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) * 100 AS mortality_percentage
  FROM base_with_groups
  GROUP BY los_group, charlson_group, sepsis_group
)

SELECT 
  los_group,
  charlson_group,
  MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN mortality_percentage END) AS mortality_no_shock,
  MAX(CASE WHEN sepsis_group = 'Septic shock' THEN mortality_percentage END) AS mortality_shock,
  MAX(CASE WHEN sepsis_group = 'Septic shock' THEN mortality_percentage END) 
    - MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN mortality_percentage END) AS absolute_difference,
  (MAX(CASE WHEN sepsis_group = 'Septic shock' THEN mortality_percentage END) 
    - MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN mortality_percentage END)) 
  / NULLIF(MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN mortality_percentage END), 0) * 100 AS relative_difference
FROM grouped
GROUP BY los_group, charlson_group
ORDER BY los_group, charlson_group;