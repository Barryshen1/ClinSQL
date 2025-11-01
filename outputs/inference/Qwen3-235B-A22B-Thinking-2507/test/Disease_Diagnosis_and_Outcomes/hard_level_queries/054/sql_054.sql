WITH age_filtered AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 59 AND 69
),

pe_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '4151')
     OR (icd_version = 10 AND icd_code IN (
       'I260', 'I2601', 'I2602', 'I2609', 'I269', 'I2690', 'I2692', 'I2699'
     ))
),

charlson_mapping AS (
  SELECT icd_code, icd_version, condition, weight
  FROM UNNEST([
    -- ICD-9 examples (full mapping required)
    STRUCT('410' AS icd_code, 9 AS icd_version, 'Myocardial infarction' AS condition, 1 AS weight),
    STRUCT('428' AS icd_code, 9 AS icd_version, 'Congestive heart failure' AS condition, 1 AS weight),
    STRUCT('438' AS icd_code, 9 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight),
    -- ICD-10 examples (full mapping required)
    STRUCT('I210' AS icd_code, 10 AS icd_version, 'Myocardial infarction' AS condition, 1 AS weight),
    STRUCT('I211' AS icd_code, 10 AS icd_version, 'Myocardial infarction' AS condition, 1 AS weight),
    STRUCT('I212' AS icd_code, 10 AS icd_version, 'Myocardial infarction' AS condition, 1 AS weight),
    STRUCT('I213' AS icd_code, 10 AS icd_version, 'Myocardial infarction' AS condition, 1 AS weight),
    STRUCT('I214' AS icd_code, 10 AS icd_version, 'Myocardial infarction' AS condition, 1 AS weight),
    STRUCT('I219' AS icd_code, 10 AS icd_version, 'Myocardial infarction' AS condition, 1 AS weight),
    STRUCT('I500' AS icd_code, 10 AS icd_version, 'Congestive heart failure' AS condition, 1 AS weight),
    STRUCT('I501' AS icd_code, 10 AS icd_version, 'Congestive heart failure' AS condition, 1 AS weight),
    STRUCT('I509' AS icd_code, 10 AS icd_version, 'Congestive heart failure' AS condition, 1 AS weight),
    STRUCT('I630' AS icd_code, 10 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight),
    STRUCT('I631' AS icd_code, 10 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight),
    STRUCT('I632' AS icd_code, 10 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight),
    STRUCT('I633' AS icd_code, 10 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight),
    STRUCT('I634' AS icd_code, 10 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight),
    STRUCT('I635' AS icd_code, 10 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight),
    STRUCT('I636' AS icd_code, 10 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight),
    STRUCT('I638' AS icd_code, 10 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight),
    STRUCT('I639' AS icd_code, 10 AS icd_version, 'Cerebrovascular disease' AS condition, 1 AS weight)
    -- Full Charlson mapping (100+ codes) should be included here
  ])
),

charlson_per_admission AS (
  SELECT 
    d.hadm_id,
    cm.condition,
    MAX(cm.weight) AS weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN charlson_mapping cm
    ON d.icd_code = cm.icd_code 
    AND d.icd_version = cm.icd_version
  GROUP BY d.hadm_id, cm.condition
),

charlson_total AS (
  SELECT 
    hadm_id,
    SUM(weight) AS charlson_score
  FROM charlson_per_admission
  GROUP BY hadm_id
),

complication_codes AS (
  SELECT icd_code, icd_version, complication_type
  FROM UNNEST([
    -- Cardiovascular complications (MI, heart failure)
    STRUCT('I210' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I211' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I212' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I213' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I214' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I219' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I220' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I221' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I228' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I229' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I500' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I501' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    STRUCT('I509' AS icd_code, 10 AS icd_version, 'cardio' AS complication_type),
    -- Neurologic complications (ischemic stroke)
    STRUCT('I630' AS icd_code, 10 AS icd_version, 'neuro' AS complication_type),
    STRUCT('I631' AS icd_code, 10 AS icd_version, 'neuro' AS complication_type),
    STRUCT('I632' AS icd_code, 10 AS icd_version, 'neuro' AS complication_type),
    STRUCT('I633' AS icd_code, 10 AS icd_version, 'neuro' AS complication_type),
    STRUCT('I634' AS icd_code, 10 AS icd_version, 'neuro' AS complication_type),
    STRUCT('I635' AS icd_code, 10 AS icd_version, 'neuro' AS complication_type),
    STRUCT('I636' AS icd_code, 10 AS icd_version, 'neuro' AS complication_type),
    STRUCT('I638' AS icd_code, 10 AS icd_version, 'neuro' AS complication_type),
    STRUCT('I639' AS icd_code, 10 AS icd_version, 'neuro' AS complication_type)
  ])
),

complications AS (
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN cc.complication_type = 'cardio' THEN 1 ELSE 0 END) AS has_cardio,
    MAX(CASE WHEN cc.complication_type = 'neuro' THEN 1 ELSE 0 END) AS has_neuro
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN complication_codes cc
    ON d.icd_code = cc.icd_code 
    AND d.icd_version = cc.icd_version
  GROUP BY d.hadm_id
),

combined AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.dod,
    a.age_at_admission,
    CASE WHEN pe.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_pe,
    COALESCE(ct.charlson_score, 0) AS charlson_score,
    COALESCE(c.has_cardio, 0) AS has_cardio,
    COALESCE(c.has_neuro, 0) AS has_neuro,
    CASE 
      WHEN a.dod IS NOT NULL 
        AND DATETIME_DIFF(a.dod, a.admittime, DAY) <= 30 
      THEN 1 
      ELSE 0 
    END AS mortality_30d,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM age_filtered a
  LEFT JOIN pe_admissions pe 
    ON a.hadm_id = pe.hadm_id
  LEFT JOIN charlson_total ct 
    ON a.hadm_id = ct.hadm_id
  LEFT JOIN complications c 
    ON a.hadm_id = c.hadm_id
),

cohorts AS (
  SELECT 
    *,
    CASE 
      WHEN has_pe = 1 AND charlson_score >= 3 THEN 'PE_high_burden'
      WHEN has_pe = 0 THEN 'non_PE'
      ELSE NULL 
    END AS group_name
  FROM combined
  WHERE has_pe IN (0, 1)  -- Exclude ambiguous cases
)

SELECT
  group_name,
  AVG(charlson_score) AS mean_charlson,
  AVG(mortality_30d) AS mortality_30d_rate,
  AVG(has_cardio) AS cardio_complication_rate,
  AVG(has_neuro) AS neuro_complication_rate,
  AVG(CASE WHEN mortality_30d = 0 THEN los END) AS survivor_los
FROM cohorts
WHERE group_name IS NOT NULL
GROUP BY group_name;