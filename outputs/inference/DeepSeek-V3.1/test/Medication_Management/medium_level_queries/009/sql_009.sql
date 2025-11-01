WITH cohort AS (
  -- Males aged 68-78 with diabetes and heart failure in the same admission
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hadm_id IN (
      -- Admissions with diabetes
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE (
        (di.icd_version = 10 AND di.icd_code LIKE 'E1%') 
        OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
      )
    )
    AND a.hadm_id IN (
      -- Admissions with heart failure
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE (
        (di.icd_version = 10 AND di.icd_code LIKE 'I50%') 
        OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
      )
    )
),

insulin_first_24h AS (
  -- Patients who started insulin in first 24h
  SELECT DISTINCT c.subject_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%insulin%'
    AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),

insulin_last_24h AS (
  -- Patients who started insulin in last 24h
  SELECT DISTINCT c.subject_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%insulin%'
    AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
),

oral_first_24h AS (
  -- Patients who started oral agent in first 24h
  SELECT DISTINCT c.subject_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE REGEXP_CONTAINS(LOWER(p.drug), r'(metformin|glipizide|glyburide|glimepiride|pioglitazone|sitagliptin|saxagliptin|linagliptin|dapagliflozin|empagliflozin|canagliflozin|repaglinide|nateglinide|tolbutamide|acarbose|miglitol)')
    AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),

oral_last_24h AS (
  -- Patients who started oral agent in last 24h
  SELECT DISTINCT c.subject_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE REGEXP_CONTAINS(LOWER(p.drug), r'(metformin|glipizide|glyburide|glimepiride|pioglitazone|sitagliptin|saxagliptin|linagliptin|dapagliflozin|empagliflozin|canagliflozin|repaglinide|nateglinide|tolbutamide|acarbose|miglitol)')
    AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
)

SELECT 
  COUNT(*) AS total_patients,
  -- Insulin rates
  COUNT(insulin_first_24h.subject_id) AS insulin_first_24h_count,
  ROUND(COUNT(insulin_first_24h.subject_id) * 100.0 / COUNT(*), 2) AS insulin_first_24h_percent,
  COUNT(insulin_last_24h.subject_id) AS insulin_last_24h_count,
  ROUND(COUNT(insulin_last_24h.subject_id) * 100.0 / COUNT(*), 2) AS insulin_last_24h_percent,
  ROUND(COUNT(insulin_first_24h.subject_id) * 100.0 / COUNT(*)
        - COUNT(insulin_last_24h.subject_id) * 100.0 / COUNT(*), 2) AS insulin_abs_diff_percent,

  -- Oral agent rates
  COUNT(oral_first_24h.subject_id) AS oral_first_24h_count,
  ROUND(COUNT(oral_first_24h.subject_id) * 100.0 / COUNT(*), 2) AS oral_first_24h_percent,
  COUNT(oral_last_24h.subject_id) AS oral_last_24h_count,
  ROUND(COUNT(oral_last_24h.subject_id) * 100.0 / COUNT(*), 2) AS oral_last_24h_percent,
  ROUND(COUNT(oral_first_24h.subject_id) * 100.0 / COUNT(*)
        - COUNT(oral_last_24h.subject_id) * 100.0 / COUNT(*), 2) AS oral_abs_diff_percent

FROM cohort c
LEFT JOIN insulin_first_24h ON c.subject_id = insulin_first_24h.subject_id
LEFT JOIN insulin_last_24h ON c.subject_id = insulin_last_24h.subject_id
LEFT JOIN oral_first_24h ON c.subject_id = oral_first_24h.subject_id
LEFT JOIN oral_last_24h ON c.subject_id = oral_last_24h.subject_id;