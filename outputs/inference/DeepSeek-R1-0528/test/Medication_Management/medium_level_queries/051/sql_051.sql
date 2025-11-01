WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.dischtime IS NOT NULL
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        -- DM ICD-9 (250.x) or ICD-10 (E10-E14)
        (icd_version = 9 AND icd_code LIKE '250%') 
        OR (icd_version = 10 AND icd_code LIKE 'E1%')
    )
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        -- HF ICD-9 (428.x) or ICD-10 (I50.x)
        (icd_version = 9 AND icd_code LIKE '428%') 
        OR (icd_version = 10 AND icd_code LIKE 'I50%')
    )
),

cohort_meds AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime,
    -- Define time windows (handle short stays)
    DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) AS early_end,
    DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AS late_start,
    e.medication,
    e.charttime
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND c.subject_id = e.subject_id
    AND e.charttime BETWEEN c.admittime AND c.dischtime
),

cohort_flags AS (
  SELECT 
    subject_id,
    hadm_id,
    -- Insulin flags
    MAX(CASE 
          WHEN charttime BETWEEN admittime AND early_end 
          AND REGEXP_CONTAINS(LOWER(medication), r'insulin|humalog|novolog|lantus|levemir|apidra|tresiba|afrezza') 
          THEN 1 ELSE 0 
        END) AS insulin_early,
    MAX(CASE 
          WHEN charttime BETWEEN late_start AND dischtime 
          AND REGEXP_CONTAINS(LOWER(medication), r'insulin|humalog|novolog|lantus|levemir|apidra|tresiba|afrezza') 
          THEN 1 ELSE 0 
        END) AS insulin_late,
    -- Oral agent flags
    MAX(CASE 
          WHEN charttime BETWEEN admittime AND early_end 
          AND REGEXP_CONTAINS(LOWER(medication), r'metformin|glipizide|glyburide|glimepiride|pioglitazone|sitagliptin|saxagliptin|linagliptin|repaglinide|dapagliflozin|empagliflozin') 
          THEN 1 ELSE 0 
        END) AS oral_early,
    MAX(CASE 
          WHEN charttime BETWEEN late_start AND dischtime 
          AND REGEXP_CONTAINS(LOWER(medication), r'metformin|glipizide|glyburide|glimepiride|pioglitazone|sitagliptin|saxagliptin|linagliptin|repaglinide|dapagliflozin|empagliflozin') 
          THEN 1 ELSE 0 
        END) AS oral_late
  FROM cohort_meds
  GROUP BY subject_id, hadm_id
)

SELECT 
  'Insulin' AS medication_class,
  COUNT(*) AS total_patients,
  ROUND(100.0 * SUM(insulin_early) / COUNT(*), 1) AS early_rate_percent,
  ROUND(100.0 * SUM(insulin_late) / COUNT(*), 1) AS late_rate_percent,
  SUM(CASE WHEN insulin_early = 1 AND insulin_late = 0 THEN 1 ELSE 0 END) AS early_only,
  SUM(CASE WHEN insulin_early = 0 AND insulin_late = 1 THEN 1 ELSE 0 END) AS late_only,
  SUM(CASE WHEN insulin_early = 1 AND insulin_late = 1 THEN 1 ELSE 0 END) AS both,
  SUM(CASE WHEN insulin_early = 0 AND insulin_late = 0 THEN 1 ELSE 0 END) AS neither
FROM cohort_flags

UNION ALL

SELECT 
  'Oral Agents' AS medication_class,
  COUNT(*) AS total_patients,
  ROUND(100.0 * SUM(oral_early) / COUNT(*), 1) AS early_rate_percent,
  ROUND(100.0 * SUM(oral_late) / COUNT(*), 1) AS late_rate_percent,
  SUM(CASE WHEN oral_early = 1 AND oral_late = 0 THEN 1 ELSE 0 END) AS early_only,
  SUM(CASE WHEN oral_early = 0 AND oral_late = 1 THEN 1 ELSE 0 END) AS late_only,
  SUM(CASE WHEN oral_early = 1 AND oral_late = 1 THEN 1 ELSE 0 END) AS both,
  SUM(CASE WHEN oral_early = 0 AND oral_late = 0 THEN 1 ELSE 0 END) AS neither
FROM cohort_flags;