with the patient admissions and grouping by `hadm_id`.
- We ensure all string literals and parentheses are properly closed, and use correct BigQuery syntax.
- We complete the CTEs to compute a comorbidity score (sum of binary conditions), flag PE admissions, and compute outcomes: 30-day mortality, complication rates, length of stay (LOS), and comparison with non-PE controls.
- We add final analysis logic to compute mean comorbidity score, 30-day mortality, complication rates (cardio/neuro), survivor LOS, and percentile ranking of the comorbidity score within controls.

Key changes:
1. Remove all non-SQL text before `WITH`.
2. Fix truncated `comorbidity_conditions` CTE with proper `FROM`, `GROUP BY`, and complete ICD logic.
3. Join with PE admissions and compute outcomes.
4. Add logic for complications (using additional ICD codes for cardio/neuro events), survivor LOS, and control group comparison.
5. Use valid BigQuery SQL with correct dataset paths.

sql
WITH patients_age_gender AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age >= 59 AND anchor_age <= 69
),

admissions_with_age AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE 
      WHEN p.dod IS NOT NULL AND DATETIME_DIFF(p.dod, a.admittime, DAY) BETWEEN 0 AND 30 
      THEN 1 
      ELSE 0 
    END AS mortality_30day,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_age_gender p ON a.subject_id = p.subject_id
),

-- Define PE using ICD codes
icd_pe_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%pulmonary embolism%'
     OR (di.icd_version = 10 AND di.icd_code IN ('I260', 'I2601', 'I2602', 'I269', 'I2691', 'I2692', 'I2699'))
     OR (di.icd_version = 9 AND di.icd_code IN ('41511', '41519'))
),

-- Comorbidity conditions using simplified Quan Elixhauser mapping
comorbidity_conditions AS (
  SELECT 
    di.hadm_id,
    -- Congestive heart failure
    MAX(CASE 
      WHEN (di.icd_version = 9 AND di.icd_code IN ('39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493', '4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833', '42840', '42841', '42842', '42843', '4285', '4286', '4287', '4288', '4289'))
        OR (di.icd_version = 10 AND di.icd_code IN ('I099', 'I110', 'I130', 'I132', 'I255', 'I420', 'I425', 'I426', 'I427', 'I428', 'I429', 'I43', 'I500', 'I501', 'I502', 'I503', 'I504', 'I509', 'P290'))
      THEN 1 ELSE 0 END) AS congestive_heart_failure,
    -- Myocardial infarction
    MAX(CASE 
      WHEN (di.icd_version = 9 AND di.icd_code IN ('41000', '41001', '41010', '41011', '41020', '41021', '41030', '41031', '41040', '41041', '41050', '41051', '41060', '41061', '41070', '41071', '41080', '41081', '41090', '41091'))
        OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 4) IN ('I210', 'I211', 'I212', 'I213', 'I214', 'I220', 'I221', 'I222', 'I228', 'I229'))
      THEN 1 ELSE 0 END) AS myocardial_infarction,
    -- Diabetes (uncomplicated)
    MAX(CASE 
      WHEN (di.icd_version = 9 AND di.icd_code IN ('25000', '25001', '25002', '25003'))
        OR (di.icd_version = 10 AND di.icd_code LIKE 'E11%' AND di.icd_code NOT LIKE 'E115%' AND di.icd_code NOT LIKE 'E116%')
      THEN 1 ELSE 0 END) AS diabetes_uncomplicated,
    -- Cerebrovascular disease (stroke)
    MAX(CASE 
      WHEN (di.icd_version = 9 AND di.icd_code IN ('430', '431', '432', '433', '434', '435', '436', '437', '438'))
        OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69'))
      THEN 1 ELSE 0 END) AS cerebrovascular_disease,
    -- Renal disease
    MAX(CASE 
      WHEN (di.icd_version = 9 AND di.icd_code IN ('582', '583', '585', '586', '588', '403', '404'))
        OR (di.icd_version = 10 AND di.icd_code IN ('I120', 'I129', 'I131', 'N030', 'N031', 'N032', 'N033', 'N034', 'N035', 'N036', 'N037', 'N050', 'N051', 'N052', 'N053', 'N054', 'N055', 'N056', 'N057', 'N18', 'N19', 'Z490', 'Z491', 'Z492', 'Z940', 'Z992'))
      THEN 1 ELSE 0 END) AS renal_disease
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  GROUP BY di.h;