with proper GROUP BY and aggregation.

sql
WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 83 AND 93
),

hf_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
     OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
),

icu_status AS (
  SELECT hadm_id, 
    CASE WHEN MAX(stay_id) IS NOT NULL THEN 1 ELSE 0 END AS had_icu
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
  GROUP BY hadm_id
),

comorbidity_definitions AS (
  SELECT 'Diabetes without complication' AS comorbidity, 9 AS icd_version, '250' AS icd_code, '250' AS pattern, 0 AS complication UNION ALL
  SELECT 'Diabetes with complication', 9, '250', '250.%', 1 UNION ALL
  SELECT 'Diabetes without complication', 10, 'E11', 'E11%', 0 UNION ALL
  SELECT 'Diabetes with complication', 10, 'E10', 'E10%', 1 UNION ALL
  SELECT 'Diabetes with complication', 10, 'E13', 'E13%', 1 UNION ALL
  SELECT 'Chronic kidney disease', 9, '585', '585%', 0 UNION ALL
  SELECT 'Chronic kidney disease', 10, 'N18', 'N18%', 0 UNION ALL
  SELECT 'Cardiac arrhythmias', 10, 'I48', 'I48%', 0 UNION ALL
  SELECT 'Cardiac arrhythmias', 9, '427', '427%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I05', 'I05%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I06', 'I06%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I07', 'I07%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I08', 'I08%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I34', 'I34%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I35', 'I35%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I36', 'I36%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I37', 'I37%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I38', 'I38%', 0 UNION ALL
  SELECT 'Valvular disease', 10, 'I39', 'I39%', 0 UNION ALL
  SELECT 'Valvular disease', 9, '424', '424%', 0 UNION ALL
  SELECT 'Pulmonary circulation disorder', 10, 'I27', 'I27%', 0 UNION ALL
  SELECT 'Pulmonary circulation disorder', 9, '416', '416%', 0 UNION ALL
  SELECT 'Peripheral vascular disorder', 10, 'I73', 'I73%', 0 UNION ALL
  SELECT 'Peripheral vascular disorder', 10, 'I70', 'I70%', 0 UNION ALL
  SELECT 'Peripheral vascular disorder', 9, '443', '443%', 0 UNION ALL
  SELECT 'Hypertension', 10, 'I10', 'I10%', 0 UNION ALL
  SELECT 'Hypertension', 10, 'I11', 'I11%', 0 UNION ALL
  SELECT 'Hypertension', 10, 'I12', 'I12%', 0 UNION ALL
  SELECT 'Hypertension', 10, 'I13', 'I13%', 0 UNION ALL
  SELECT 'Hypertension', 10, 'I15', 'I15%', 0 UNION ALL
  SELECT 'Hypertension', 9, '401', '401%', 0 UNION ALL
  SELECT 'Hypertension', 9, '402', '402%', 0 UNION ALL
  SELECT 'Hypertension', 9, '403', '403%', 0
),

admission_comorbidities AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN cd.comorbidity = 'Chronic kidney disease' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN cd.comorbidity LIKE 'Diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    COUNT(DISTINCT cd.comorbidity) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN comorbidity_definitions cd 
    ON di.icd_version = cd.icd_version 
    AND di.icd_code LIKE cd.pattern
  GROUP BY di.hadm_id
),

cohort AS (
  SELECT 
    h.hadm_id,
    h.subject_id,
    h.los_days,
    h.hospital_expire_flag,
    COALESCE(i.had_icu, 0) AS had_icu,
    CASE WHEN h.los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
    CASE 
      WHEN ac.comorbidity_count <= 1 THEN '0-1'
      WHEN ac.comorbidity_count = 2 THEN '2'
      WHEN ac.comorbidity_count >= 3 THEN '>=3'
      ELSE '0-1' -- fallback
    END AS comorbidity_group,
    ac.has_ckd,
    ac.has_diabetes
  FROM hf_admissions h
  LEFT JOIN icu_status i ON h.hadm_id = i.hadm_id
  LEFT JOIN admission_comorbidities ac ON h.hadm_id = ac.hadm_id
)

SELECT;