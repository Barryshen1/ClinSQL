WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'E11%') OR
          (di.icd_version = 9 AND di.icd_code LIKE '250%' AND (di.icd_code LIKE '%0' OR di.icd_code LIKE '%2'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'I50%') OR
          (di.icd_version = 9 AND di.icd_code LIKE '428%')
        )
    )
),
meds_first48 AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN LOWER(e.medication) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin,
    MAX(CASE WHEN LOWER(e.medication) LIKE '%metformin%' OR 
                 LOWER(e.medication) LIKE '%glipizide%' OR
                 LOWER(e.medication) LIKE '%glyburide%' OR
                 LOWER(e.medication) LIKE '%glimepiride%' OR
                 LOWER(e.medication) LIKE '%pioglitazone%' OR
                 LOWER(e.medication) LIKE '%sitagliptin%' OR
                 LOWER(e.medication) LIKE '%saxagliptin%' OR
                 LOWER(e.medication) LIKE '%linagliptin%' OR
                 LOWER(e.medication) LIKE '%dapagliflozin%' OR
                 LOWER(e.medication) LIKE '%empagliflozin%' OR
                 LOWER(e.medication) LIKE '%canagliflozin%' OR
                 LOWER(e.medication) LIKE '%repaglinide%' OR
                 LOWER(e.medication) LIKE '%nateglinide%' OR
                 LOWER(e.medication) LIKE '%acarbose%' OR
                 LOWER(e.medication) LIKE '%miglitol%' THEN 1 ELSE 0 END) AS oral
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
meds_final24 AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN LOWER(e.medication) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin,
    MAX(CASE WHEN LOWER(e.medication) LIKE '%metformin%' OR 
                 LOWER(e.medication) LIKE '%glipizide%' OR
                 LOWER(e.medication) LIKE '%glyburide%' OR
                 LOWER(e.medication) LIKE '%glimepiride%' OR
                 LOWER(e.medication) LIKE '%pioglitazone%' OR
                 LOWER(e.medication) LIKE '%sitagliptin%' OR
                 LOWER(e.medication) LIKE '%saxagliptin%' OR
                 LOWER(e.medication) LIKE '%linagliptin%' OR
                 LOWER(e.medication) LIKE '%dapagliflozin%' OR
                 LOWER(e.medication) LIKE '%empagliflozin%' OR
                 LOWER(e.medication) LIKE '%canagliflozin%' OR
                 LOWER(e.medication) LIKE '%repaglinide%' OR
                 LOWER(e.medication) LIKE '%nateglinide%' OR
                 LOWER(e.medication) LIKE '%acarbose%' OR
                 LOWER(e.medication) LIKE '%miglitol%' THEN 1 ELSE 0 END) AS oral
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE e.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
  GROUP BY c.subject_id, c.hadm_id
)
SELECT 
  'First 48h' AS time_period,
  COUNT(*) AS total_patients,
  ROUND(100 * SUM(insulin) / COUNT(*), 2) AS pct_insulin,
  ROUND(100 * SUM(oral) / COUNT(*), 2) AS pct_oral
FROM meds_first48
UNION ALL
SELECT 
  'Final 24h' AS time_period,
  COUNT(*) AS total_patients,
  ROUND(100 * SUM(insulin) / COUNT(*), 2) AS pct_insulin,
  ROUND(100 * SUM(oral) / COUNT(*), 2) AS pct_oral
FROM meds_final24;