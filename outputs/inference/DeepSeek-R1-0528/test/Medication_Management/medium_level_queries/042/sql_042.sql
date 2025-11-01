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
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = p.subject_id
        AND diag.hadm_id = a.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '250%') OR
          (diag.icd_version = 10 AND diag.icd_code LIKE 'E1%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = p.subject_id
        AND diag.hadm_id = a.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%') OR
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),

first_48h AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE 
        WHEN LOWER(e.medication) LIKE '%insulin%' OR LOWER(ed.product_description) LIKE '%insulin%' 
        THEN 1 ELSE 0 
    END) AS insulin_flag,
    MAX(CASE 
        WHEN LOWER(ed.route) IN ('po', 'oral', 'by mouth', 'p.o.', 'per os')
        AND (
          LOWER(e.medication) LIKE '%metformin%' OR
          LOWER(e.medication) LIKE '%glipizide%' OR
          LOWER(e.medication) LIKE '%glyburide%' OR
          LOWER(e.medication) LIKE '%glimepiride%' OR
          LOWER(e.medication) LIKE '%pioglitazone%' OR
          LOWER(e.medication) LIKE '%rosiglitazone%' OR
          LOWER(e.medication) LIKE '%sitagliptin%' OR
          LOWER(e.medication) LIKE '%saxagliptin%' OR
          LOWER(e.medication) LIKE '%linagliptin%' OR
          LOWER(e.medication) LIKE '%alogliptin%' OR
          LOWER(e.medication) LIKE '%repaglinide%' OR
          LOWER(e.medication) LIKE '%nateglinide%' OR
          LOWER(e.medication) LIKE '%acarbose%' OR
          LOWER(e.medication) LIKE '%miglitol%' OR
          LOWER(e.medication) LIKE '%empagliflozin%' OR
          LOWER(e.medication) LIKE '%dapagliflozin%' OR
          LOWER(e.medication) LIKE '%canagliflozin%' OR
          LOWER(e.medication) LIKE '%ertugliflozin%' OR
          LOWER(ed.product_description) LIKE '%metformin%' OR
          LOWER(ed.product_description) LIKE '%glipizide%' OR
          LOWER(ed.product_description) LIKE '%glyburide%' OR
          LOWER(ed.product_description) LIKE '%glimepiride%' OR
          LOWER(ed.product_description) LIKE '%pioglitazone%' OR
          LOWER(ed.product_description) LIKE '%rosiglitazone%' OR
          LOWER(ed.product_description) LIKE '%sitagliptin%' OR
          LOWER(ed.product_description) LIKE '%saxagliptin%' OR
          LOWER(ed.product_description) LIKE '%linagliptin%' OR
          LOWER(ed.product_description) LIKE '%alogliptin%' OR
          LOWER(ed.product_description) LIKE '%repaglinide%' OR
          LOWER(ed.product_description) LIKE '%nateglinide%' OR
          LOWER(ed.product_description) LIKE '%acarbose%' OR
          LOWER(ed.product_description) LIKE '%miglitol%' OR
          LOWER(ed.product_description) LIKE '%empagliflozin%' OR
          LOWER(ed.product_description) LIKE '%dapagliflozin%' OR
          LOWER(ed.product_description) LIKE '%canagliflozin%' OR
          LOWER(ed.product_description) LIKE '%ertugliflozin%'
        ) 
        THEN 1 ELSE 0 
    END) AS oral_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id 
    AND c.hadm_id = e.hadm_id
    AND e.charttime BETWEEN c.admittime 
      AND LEAST(DATETIME_ADD(c.admittime, INTERVAL 48 HOUR), c.dischtime)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id 
    AND e.emar_seq = ed.emar_seq
  GROUP BY c.subject_id, c.hadm_id
),

final_24h AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE 
        WHEN LOWER(e.medication) LIKE '%insulin%' OR LOWER(ed.product_description) LIKE '%insulin%' 
        THEN 1 ELSE 0 
    END) AS insulin_flag,
    MAX(CASE 
        WHEN LOWER(ed.route) IN ('po', 'oral', 'by mouth', 'p.o.', 'per os')
        AND (
          LOWER(e.medication) LIKE '%metformin%' OR
          LOWER(e.medication) LIKE '%glipizide%' OR
          LOWER(e.medication) LIKE '%glyburide%' OR
          LOWER(e.medication) LIKE '%glimepiride%' OR
          LOWER(e.medication) LIKE '%pioglitazone%' OR
          LOWER(e.medication) LIKE '%rosiglitazone%' OR
          LOWER(e.medication) LIKE '%sitagliptin%' OR
          LOWER(e.medication) LIKE '%saxagliptin%' OR
          LOWER(e.medication) LIKE '%linagliptin%' OR
          LOWER(e.medication) LIKE '%alogliptin%' OR
          LOWER(e.medication) LIKE '%repaglinide%' OR
          LOWER(e.medication) LIKE '%nateglinide%' OR
          LOWER(e.medication) LIKE '%acarbose%' OR
          LOWER(e.medication) LIKE '%miglitol%' OR
          LOWER(e.medication) LIKE '%empagliflozin%' OR
          LOWER(e.medication) LIKE '%dapagliflozin%' OR
          LOWER(e.medication) LIKE '%canagliflozin%' OR
          LOWER(e.medication) LIKE '%ertugliflozin%' OR
          LOWER(ed.product_description) LIKE '%metformin%' OR
          LOWER(ed.product_description) LIKE '%glipizide%' OR
          LOWER(ed.product_description) LIKE '%glyburide%' OR
          LOWER(ed.product_description) LIKE '%glimepiride%' OR
          LOWER(ed.product_description) LIKE '%pioglitazone%' OR
          LOWER(ed.product_description) LIKE '%rosiglitazone%' OR
          LOWER(ed.product_description) LIKE '%sitagliptin%' OR
          LOWER(ed.product_description) LIKE '%saxagliptin%' OR
          LOWER(ed.product_description) LIKE '%linagliptin%' OR
          LOWER(ed.product_description) LIKE '%alogliptin%' OR
          LOWER(ed.product_description) LIKE '%repaglinide%' OR
          LOWER(ed.product_description) LIKE '%nateglinide%' OR
          LOWER(ed.product_description) LIKE '%acarbose%' OR
          LOWER(ed.product_description) LIKE '%miglitol%' OR
          LOWER(ed.product_description) LIKE '%empagliflozin%' OR
          LOWER(ed.product_description) LIKE '%dapagliflozin%' OR
          LOWER(ed.product_description) LIKE '%canagliflozin%' OR
          LOWER(ed.product_description) LIKE '%ertugliflozin%'
        ) 
        THEN 1 ELSE 0 
    END) AS oral_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id 
    AND c.hadm_id = e.hadm_id
    AND e.charttime BETWEEN 
      GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR)) 
      AND c.dischtime
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id 
    AND e.emar_seq = ed.emar_seq
  GROUP BY c.subject_id, c.hadm_id
),

combined AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COALESCE(f.insulin_flag, 0) AS insulin_first48,
    COALESCE(f.oral_flag, 0) AS oral_first48,
    COALESCE(l.insulin_flag, 0) AS insulin_last24,
    COALESCE(l.oral_flag, 0) AS oral_last24
  FROM cohort c
  LEFT JOIN first_48h f 
    ON c.subject_id = f.subject_id 
    AND c.hadm_id = f.hadm_id
  LEFT JOIN final_24h l 
    ON c.subject_id = l.subject_id 
    AND c.hadm_id = l.hadm_id
),

percent_summary AS (
  SELECT 
    'First 48h' AS time_window,
    ROUND(100 * AVG(insulin_first48), 2) AS insulin_pct,
    ROUND(100 * AVG(oral_first48), 2) AS oral_pct
  FROM combined
  UNION ALL
  SELECT 
    'Final 24h' AS time_window,
    ROUND(100 * AVG(insulin_last24), 2) AS insulin_pct,
    ROUND(100 * AVG(oral_last24), 2) AS oral_pct
  FROM combined
),

count_summary AS (
  SELECT 
    'Insulin' AS medication_type,
    SUM(CASE WHEN insulin_first48 = 1 AND insulin_last24 = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN insulin_first48 = 0 AND insulin_last24 = 1 THEN 1 ELSE 0 END) AS initiated,
    SUM(CASE WHEN insulin_first48 = 1 AND insulin_last24 = 0 THEN 1 ELSE 0 END) AS discontinued
  FROM combined
  UNION ALL
  SELECT 
    'Oral Agents' AS medication_type,
    SUM(CASE WHEN oral_first48 = 1 AND oral_last24 = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN oral_first48 = 0 AND oral_last24 = 1 THEN 1 ELSE 0 END) AS initiated,
    SUM(CASE WHEN oral_first48 = 1 AND oral_last24 = 0 THEN 1 ELSE 0 END) AS discontinued
  FROM combined
)

SELECT 
  'percent' AS result_type,
  time_window,
  insulin_pct,
  oral_pct,
  NULL AS medication_type,
  NULL AS continued,
  NULL AS initiated,
  NULL AS discontinued
FROM percent_summary
UNION ALL
SELECT 
  'count' AS result_type,
  NULL AS time_window,
  NULL AS insulin_pct,
  NULL AS oral_pct,
  medication_type,
  continued,
  initiated,
  discontinued
FROM count_summary;