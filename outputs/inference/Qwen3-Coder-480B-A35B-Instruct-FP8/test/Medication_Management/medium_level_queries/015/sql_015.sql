WITH target_patients AS (
  SELECT DISTINCT
    p.subject_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1 ON a.hadm_id = d1.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd1 ON d1.icd_code = dd1.icd_code AND d1.icd_version = dd1.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2 ON a.hadm_id = d2.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd2 ON d2.icd_code = dd2.icd_code AND d2.icd_version = dd2.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND (
      (dd1.icd_code LIKE 'E10%' OR dd1.icd_code LIKE 'E11%' OR dd1.icd_code LIKE 'E14%')
      OR LOWER(dd1.long_title) LIKE '%diabetes%'
    )
    AND (
      dd2.icd_code LIKE 'I50%'
      OR LOWER(dd2.long_title) LIKE '%heart failure%'
    )
    AND i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
    AND i.outtime > i.intime + INTERVAL 24 HOUR
),

first_24h_meds AS (
  SELECT DISTINCT
    tp.subject_id,
    CASE
      WHEN LOWER(e.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(e.medication) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(e.medication) LIKE '%glipizide%' OR LOWER(e.medication) LIKE '%glyburide%' THEN 'Sulfonylurea'
      WHEN LOWER(e.medication) LIKE '%sitagliptin%' OR LOWER(e.medication) LIKE '%saxagliptin%' THEN 'DPP-4'
      WHEN LOWER(e.medication) LIKE '%empagliflozin%' OR LOWER(e.medication) LIKE '%dapagliflozin%' THEN 'SGLT2'
      WHEN LOWER(e.medication) LIKE '%liraglutide%' OR LOWER(e.medication) LIKE '%semaglutide%' THEN 'GLP-1'
      WHEN LOWER(e.medication) LIKE '%pioglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM
    target_patients tp
  JOIN
    physionet-data.mimiciv_3_1_hosp.emar e ON tp.subject_id = e.subject_id
  WHERE
    e.charttime >= tp.intime
    AND e.charttime <= tp.intime + INTERVAL 24 HOUR
    AND e.medication IS NOT NULL
),

last_12h_meds AS (
  SELECT DISTINCT
    tp.subject_id,
    CASE
      WHEN LOWER(e.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(e.medication) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(e.medication) LIKE '%glipizide%' OR LOWER(e.medication) LIKE '%glyburide%' THEN 'Sulfonylurea'
      WHEN LOWER(e.medication) LIKE '%sitagliptin%' OR LOWER(e.medication) LIKE '%saxagliptin%' THEN 'DPP-4'
      WHEN LOWER(e.medication) LIKE '%empagliflozin%' OR LOWER(e.medication) LIKE '%dapagliflozin%' THEN 'SGLT2'
      WHEN LOWER(e.medication) LIKE '%liraglutide%' OR LOWER(e.medication) LIKE '%semaglutide%' THEN 'GLP-1'
      WHEN LOWER(e.medication) LIKE '%pioglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM
    target_patients tp
  JOIN
    physionet-data.mimiciv_3_1_hosp.emar e ON tp.subject_id = e.subject_id
  WHERE
    e.charttime >= tp.outtime - INTERVAL 12 HOUR
    AND e.charttime <= tp.outtime
    AND e.medication IS NOT NULL
),

drug_class_list AS (
  SELECT 'Insulin' AS drug_class
  UNION ALL SELECT 'Metformin'
  UNION ALL SELECT 'Sulfonylurea'
  UNION ALL SELECT 'DPP-4'
  UNION ALL SELECT 'SGLT2'
  UNION ALL SELECT 'GLP-1'
  UNION ALL SELECT 'TZD'
),

first_24h_counts AS (
  SELECT
    drug_class,
    COUNT(DISTINCT subject_id) AS count_first
  FROM
    first_24h_meds
  WHERE
    drug_class IS NOT NULL
  GROUP BY
    drug_class
),

last_12h_counts AS (
  SELECT
    drug_class,
    COUNT(DISTINCT subject_id) AS count_last
  FROM
    last_12h_meds
  WHERE
    drug_class IS NOT NULL
  GROUP BY
    drug_class
),

total_patients AS (
  SELECT COUNT(DISTINCT subject_id) AS total_n
  FROM target_patients
)

SELECT
  dcl.drug_class,
  ROUND(COALESCE(f24.count_first, 0) * 100.0 / tp.total_n, 2) AS percent_first_24h,
  ROUND(COALESCE(l12.count_last, 0) * 100.0 / tp.total_n, 2) AS percent_final_12h,
  ROUND((COALESCE(l12.count_last, 0) * 100.0 / tp.total_n) - (COALESCE(f24.count_first, 0) * 100.0 / tp.total_n), 2) AS net_change_pp
FROM
  drug_class_list dcl
LEFT JOIN
  first_24h_counts f24 ON dcl.drug_class = f24.drug_class
LEFT JOIN
  last_12h_counts l12 ON dcl.drug_class = l12.drug_class
CROSS JOIN
  total_patients tp
ORDER BY
  dcl.drug_class;