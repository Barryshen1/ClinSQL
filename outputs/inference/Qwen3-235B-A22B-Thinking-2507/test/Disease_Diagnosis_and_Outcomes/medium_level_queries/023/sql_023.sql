WITH /* Step 1: Get female patients aged 52-62 */
cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 52 AND 62
),

/* Step 2: Define stroke codes */
stroke_codes AS (
  -- Define stroke ICD codes
  SELECT 'ischemic' AS stroke_type, '9' AS icd_version, code
  FROM UNNEST([
    '43400', '43401', '43410', '43411', '43490', '43491',
    '43300', '43301', '43310', '43311', '43320', '43321',
    '43330', '43331', '43380', '43381', '43390', '43391', '436'
  ]) AS code
  
  UNION ALL
  
  SELECT 'ischemic', '10', code
  FROM UNNEST([
    'I630', 'I631', 'I632', 'I633', 'I634', 'I635', 'I636', 'I638', 'I639'
  ]) AS code
  
  UNION ALL
  
  SELECT 'hemorrhagic', '9', code
  FROM UNNEST(['430', '431', '432']) AS code
  
  UNION ALL
  
  SELECT 'hemorrhagic', '10', code
  FROM UNNEST(['I60', 'I61', 'I62']) AS code
),

/* Step 3: Identify stroke patients and type */
stroke_diagnoses AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN sc.stroke_type = 'ischemic' THEN 1 ELSE 0 END) AS has_ischemic,
    MAX(CASE WHEN sc.stroke_type = 'hemorrhagic' THEN 1 ELSE 0 END) AS has_hemorrhagic
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON c.hadm_id = d.hadm_id
  LEFT JOIN stroke_codes sc
    ON d.icd_code = sc.code AND CAST(d.icd_version AS STRING) = sc.icd_version
  GROUP BY c.hadm_id
),

stroke_patients AS (
  SELECT 
    c.*,
    CASE 
      WHEN sd.has_ischemic = 1 AND sd.has_hemorrhagic = 0 THEN 'ischemic'
      WHEN sd.has_ischemic = 0 AND sd.has_hemorrhagic = 1 THEN 'hemorrhagic'
    END AS stroke_group,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort c
  INNER JOIN stroke_diagnoses sd
    ON c.hadm_id = sd.hadm_id
  WHERE (sd.has_ischemic = 1 AND sd.has_hemorrhagic = 0)
     OR (sd.has_ischemic = 0 AND sd.has_hemorrhagic = 1)
),

/* Step 4: Calculate comorbidities */
comorbidity_conditions AS (
  -- Define chronic conditions for comorbidity index
  SELECT 'diabetes' AS condition, '9' AS icd_version, code
  FROM UNNEST(['250']) AS code  -- Prefix for diabetes in ICD-9
  
  UNION ALL
  
  SELECT 'diabetes', '10', code
  FROM UNNEST(['E08', 'E09', 'E10', 'E11', 'E12', 'E13']) AS code  -- Diabetes in ICD-10
  
  UNION ALL
  
  SELECT 'ckd', '9', code
  FROM UNNEST(['585']) AS code  -- CKD in ICD-9
  
  UNION ALL
  
  SELECT 'ckd', '10', code
  FROM UNNEST(['N18']) AS code  -- CKD in ICD-10
),

patient_comorbidities AS (
  SELECT 
    sp.hadm_id,
    sp.stroke_group,
    sp.hospital_expire_flag,
    sp.los_days,
    COUNT(DISTINCT cc.condition) AS comorbidity_score,
    MAX(CASE WHEN cc.condition = 'ckd' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN cc.condition = 'diabetes' THEN 1 ELSE 0 END) AS has_diabetes
  FROM stroke_patients sp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON sp.hadm_id = d.hadm_id
  LEFT JOIN comorbidity_conditions cc
    ON d.icd_code LIKE cc.code || '%'  -- Prefix match for ICD codes
    AND CAST(d.icd_version AS STRING) = cc.icd_version
  GROUP BY sp.hadm_id, sp.stroke_group, sp.hospital_expire_flag, sp.los_days
),

comorbidity_tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (PARTITION BY stroke_group ORDER BY comorbidity_score) AS comorbidity_tertile
  FROM patient_comorbidities
)

/* Final results */
SELECT
  stroke_group,
  'overall' AS category,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(CASE WHEN los_days < 8 THEN 1 ELSE 0 END) AS los_lt_8_days,
  AVG(CASE WHEN los_days >= 8 THEN 1 ELSE 0 END) AS los_gte_8_days,
  NULL AS comorbidity_tertile,
  NULL AS ckd_prevalence,
  NULL AS diabetes_prevalence
FROM patient_comorbidities
GROUP BY stroke_group

UNION ALL

SELECT
  ct.stroke_group,
  'comorbidity_tertile_' || CAST(ct.comorbidity_tertile AS STRING) AS category,
  NULL AS mortality_rate,
  NULL AS los_lt_8_days,
  NULL AS los_gte_8_days,
  ct.comorbidity_tertile,
  AVG(CAST(ct.has_ckd AS FLOAT64)) AS ckd_prevalence,
  AVG(CAST(ct.has_diabetes AS FLOAT64)) AS diabetes_prevalence
FROM comorbidity_tertiles ct
GROUP BY ct.stroke_group, ct.comorbidity_tertile, category;