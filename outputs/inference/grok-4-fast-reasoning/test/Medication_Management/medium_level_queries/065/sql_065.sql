WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 77 AND 87
),
dm_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'))
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort_diag AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN dm_hadm d ON c.hadm_id = d.hadm_id
  INNER JOIN hf_hadm h ON c.hadm_id = h.hadm_id
),
total_n AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_patients
  FROM cohort_diag
),
early_insulin_n AS (
  SELECT COUNT(DISTINCT p.hadm_id) AS early_insulin_patients
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort_diag c ON p.hadm_id = c.hadm_id
  WHERE LOWER(p.drug) LIKE '%insulin%'
    AND p.starttime >= c.admittime
    AND p.starttime <= c.admittime + INTERVAL 48 HOUR
),
early_oral_n AS (
  SELECT COUNT(DISTINCT p.hadm_id) AS early_oral_patients
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort_diag c ON p.hadm_id = c.hadm_id
  WHERE p.route = 'PO'
    AND (
      LOWER(p.drug) LIKE '%metformin%' OR
      LOWER(p.drug) LIKE '%glipizide%' OR
      LOWER(p.drug) LIKE '%glyburide%' OR
      LOWER(p.drug) LIKE '%glimepiride%' OR
      LOWER(p.drug) LIKE '%pioglitazone%' OR
      LOWER(p.drug) LIKE '%repaglinide%' OR
      LOWER(p.drug) LIKE '%sitagliptin%' OR
      LOWER(p.drug) LIKE '%acarbose%' OR
      LOWER(p.drug) LIKE '%nateglinide%' OR
      LOWER(p.drug) LIKE '%saxagliptin%'
    )
    AND p.starttime >= c.admittime
    AND p.starttime <= c.admittime + INTERVAL 48 HOUR
),
late_insulin_n AS (
  SELECT COUNT(DISTINCT p.hadm_id) AS late_insulin_patients
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort_diag c ON p.hadm_id = c.hadm_id
  WHERE LOWER(p.drug) LIKE '%insulin%'
    AND p.starttime >= c.dischtime - INTERVAL 72 HOUR
    AND p.starttime <= c.dischtime
),
late_oral_n AS (
  SELECT COUNT(DISTINCT p.hadm_id) AS late_oral_patients
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort_diag c ON p.hadm_id = c.hadm_id
  WHERE p.route = 'PO'
    AND (
      LOWER(p.drug) LIKE '%metformin%' OR
      LOWER(p.drug) LIKE '%glipizide%' OR
      LOWER(p.drug) LIKE '%glyburide%' OR
      LOWER(p.drug) LIKE '%glimepiride%' OR
      LOWER(p.drug) LIKE '%pioglitazone%' OR
      LOWER(p.drug) LIKE '%repaglinide%' OR
      LOWER(p.drug) LIKE '%sitagliptin%' OR
      LOWER(p.drug) LIKE '%acarbose%' OR
      LOWER(p.drug) LIKE '%nateglinide%' OR
      LOWER(p.drug) LIKE '%saxagliptin%'
    )
    AND p.starttime >= c.dischtime - INTERVAL 72 HOUR
    AND p.starttime <= c.dischtime
)
SELECT
  t.total_patients,
  ei.early_insulin_patients,
  ROUND(ei.early_insulin_patients * 100.0 / t.total_patients, 2) AS early_insulin_rate_pct,
  eo.early_oral_patients,
  ROUND(eo.early_oral_patients * 100.0 / t.total_patients, 2) AS early_oral_rate_pct,
  li.late_insulin_patients,
  ROUND(li.late_insulin_patients * 100.0 / t.total_patients, 2) AS late_insulin_rate_pct,
  lo.late_oral_patients,
  ROUND(lo.late_oral_patients * 100.0 / t.total_patients, 2) AS late_oral_rate_pct,
  ROUND(li.late_insulin_patients * 100.0 / t.total_patients - ei.early_insulin_patients * 100.0 / t.total_patients, 2) AS net_change_insulin_pp,
  ROUND(lo.late_oral_patients * 100.0 / t.total_patients - eo.early_oral_patients * 100.0 / t.total_patients, 2) AS net_change_oral_pp
FROM total_n t
CROSS JOIN early_insulin_n ei
CROSS JOIN early_oral_n eo
CROSS JOIN late_insulin_n li
CROSS JOIN late_oral_n lo;