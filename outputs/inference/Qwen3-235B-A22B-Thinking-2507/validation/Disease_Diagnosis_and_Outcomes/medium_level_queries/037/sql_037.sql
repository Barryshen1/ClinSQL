WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL  -- Only discharged patients
),
sepsis_admissions AS (
  SELECT c.*
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = c.hadm_id
      AND d.icd_version = 10
      AND (
        d.icd_code LIKE 'A40%' 
        OR d.icd_code LIKE 'A41%' 
        OR d.icd_code = 'R6520' 
        OR d.icd_code = 'R6521'
      )
  )
),
sepsis_severity AS (
  SELECT 
    sa.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = sa.hadm_id 
          AND d.icd_version = 10 
          AND d.icd_code = 'R6521'
      ) THEN 'septic shock'
      ELSE 'no shock'
    END AS sepsis_severity
  FROM sepsis_admissions sa
),
charlson_conditions AS (
  SELECT 
    d.hadm_id,
    CASE 
      -- Myocardial infarction (I21-I25 excluding I25.2, I25.5, I25.8)
      WHEN d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' 
        OR d.icd_code LIKE 'I24%' OR (d.icd_code LIKE 'I25%' AND d.icd_code NOT IN ('I252', 'I255', 'I258')) 
        THEN 'mi'
      -- Congestive heart failure (I50, I09.9, I11.0, I13.0, I13.2, I25.5, I42.0, I42.5-I42.9, P29.0)
      WHEN d.icd_code LIKE 'I50%' OR d.icd_code = 'I099' OR d.icd_code = 'I110' 
        OR d.icd_code = 'I130' OR d.icd_code = 'I132' OR d.icd_code = 'I255' 
        OR d.icd_code LIKE 'I420%' OR (d.icd_code LIKE 'I42%' AND d.icd_code NOT BETWEEN 'I421' AND 'I424')
        OR d.icd_code LIKE 'P290%' 
        THEN 'chf'
      -- Cerebrovascular disease (I60-I69, G45-G46, G93.2, I67.4, I67.8-I67.9)
      WHEN (d.icd_code LIKE 'I6%' AND d.icd_code NOT BETWEEN 'I68' AND 'I69') 
        OR d.icd_code LIKE 'G45%' OR d.icd_code LIKE 'G46%' OR d.icd_code = 'G932'
        OR d.icd_code = 'I674' OR d.icd_code = 'I678' OR d.icd_code = 'I679'
        THEN 'cerebrovascular'
      -- Peripheral vascular disease (I70-I79, K55, Q27.1, I25.1, I25.8)
      WHEN d.icd_code LIKE 'I7%' OR d.icd_code LIKE 'K55%' OR d.icd_code = 'Q271'
        OR d.icd_code = 'I251' OR d.icd_code = 'I258'
        THEN 'pvod'
      -- Hypertension (I10-I15)
      WHEN d.icd_code LIKE 'I1%' AND d.icd_code < 'I20'
        THEN 'hypertension'
      -- Chronic pulmonary disease (J40-J47, I27.8, I27.9, J86.9, J96.1, J96.9)
      WHEN (d.icd_code LIKE 'J4%' OR d.icd_code LIKE 'J86%' OR d.icd_code LIKE 'J96%')
        OR d.icd_code = 'I278' OR d.icd_code = 'I279'
        THEN 'pulmonary'
      -- Other conditions (simplified; full mapping required in practice)
      WHEN d.icd_code LIKE 'I10%' THEN 'hypertension'
      WHEN d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%' THEN 'diabetes'
      WHEN d.icd_code LIKE 'N18%' OR d.icd_code = 'N19' THEN 'renal'
      WHEN d.icd_code LIKE 'I85%' OR d.icd_code LIKE 'I86%' OR d.icd_code LIKE 'I98%' 
        OR d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K71%' OR d.icd_code LIKE 'K73%' 
        OR d.icd_code LIKE 'K74%' OR d.icd_code = 'Z944'
        THEN 'liver'
      WHEN d.icd_code LIKE 'C81%' OR d.icd_code LIKE 'C82%' OR d.icd_code LIKE 'C83%' 
        OR d.icd_code LIKE 'C84%' OR d.icd_code LIKE 'C85%' OR d.icd_code LIKE 'C86%' 
        OR d.icd_code LIKE 'C90%' OR d.icd_code LIKE 'C91%' OR d.icd_code LIKE 'C92%' 
        OR d.icd_code LIKE 'C93%' OR d.icd_code LIKE 'C94%' OR d.icd_code LIKE 'C95%' 
        OR d.icd_code LIKE 'C96%' OR d.icd_code LIKE 'D47%' OR d.icd_code LIKE 'D771%'
        THEN 'cancer'
      -- Add remaining 17 conditions per Charlson in full implementation
      ELSE NULL
    END AS condition_group
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN sepsis_admissions sa
    ON d.hadm_id = sa.hadm_id
  WHERE d.icd_version = 10
),
comorbidity_counts AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT condition_group) AS comorbidity_count
  FROM charlson_conditions
  GROUP BY hadm_id
)
SELECT
  ss.sepsis_severity,
  CASE 
    WHEN ss.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN ss.los_days BETWEEN 4 AND 7 THEN '4-7'
    WHEN ss.los_days >= 8 THEN '>=8'
  END AS los_group,
  ss.admission_type,
  AVG(ss.hospital_expire_flag) * 100 AS mortality_pct,
  AVG(cc.comorbidity_count) AS mean_comorbidity_count
FROM sepsis_severity ss
INNER JOIN comorbidity_counts cc
  ON ss.hadm_id = cc.hadm_id
WHERE ss.los_days >= 1  -- Only include admissions in defined LOS categories
GROUP BY sepsis_severity, los_group, admission_type
ORDER BY sepsis_severity, 
         CASE los_group 
           WHEN '1-3' THEN 1 
           WHEN '4-7' THEN 2 
           ELSE 3 
         END,
         admission_type;