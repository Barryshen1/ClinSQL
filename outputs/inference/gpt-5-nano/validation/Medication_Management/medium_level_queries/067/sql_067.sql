WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE
    LOWER(p.gender) IN ('m', 'male', 'man')
    -- age at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
    -- Must have diabetes on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- Must have acute HF on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON dd2.icd_code = di2.icd_code AND dd2.icd_version = di2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND LOWER(dd2.long_title) LIKE '%heart failure%'
    )
),

class_list AS (
  SELECT 'INSULIN' AS class_label UNION ALL
  SELECT 'METFORMIN' UNION ALL
  SELECT 'SULFONYLUREA' UNION ALL
  SELECT 'DPP-4' UNION ALL
  SELECT 'SGLT2' UNION ALL
  SELECT 'GLP-1' UNION ALL
  SELECT 'TZD'
),

drug_classification AS (
  SELECT
    sp.subject_id,
    sp.hadm_id,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(sp.drug), '(insulin)') THEN 'INSULIN'
      WHEN REGEXP_CONTAINS(LOWER(sp.drug), '(metformin)') THEN 'METFORMIN'
      WHEN REGEXP_CONTAINS(LOWER(sp.drug), '(glipizide|glyburide|glimepiride|glibenclamide)') THEN 'SULFONYLUREA'
      WHEN REGEXP_CONTAINS(LOWER(sp.drug), '(sitagliptin|linagliptin|saxagliptin|alogliptin|vildagliptin)') THEN 'DPP-4'
      WHEN REGEXP_CONTAINS(LOWER(sp.drug), '(dapagliflozin|empagliflozin|canagliflozin|ertugliflozin)') THEN 'SGLT2'
      WHEN REGEXP_CONTAINS(LOWER(sp.drug), '(liraglutide|dulaglutide|exenatide|lixisenatide|albiglutide|semaglutide)') THEN 'GLP-1'
      WHEN REGEXP_CONTAINS(LOWER(sp.drug), '(pioglitazone|rosiglitazone)') THEN 'TZD'
      ELSE NULL
    END AS drug_class,
    sp.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS sp
  WHERE sp.starttime IS NOT NULL
),

per_adm_class AS (
  SELECT
    e.hadm_id,
    cl.class_label,
    MAX(IF(dc.drug_class = cl.class_label
           AND TIMESTAMP_DIFF(dc.starttime, e.admittime, SECOND) >= 0
           AND TIMESTAMP_DIFF(dc.starttime, e.admittime, SECOND) <= 12 * 3600,
           1, 0)) AS first12h_flag,
    MAX(IF(dc.drug_class = cl.class_label
           AND TIMESTAMP_DIFF(e.dischtime, dc.starttime, SECOND) >= 0
           AND TIMESTAMP_DIFF(e.dischtime, dc.starttime, SECOND) <= 48 * 3600,
           1, 0)) AS final48h_flag
  FROM eligible_admissions e
  CROSS JOIN class_list cl
  LEFT JOIN drug_classification dc
    ON dc.subject_id = e.subject_id
   AND dc.hadm_id = e.hadm_id
  GROUP BY e.hadm_id, cl.class_label
)

SELECT
  class_label,
  SUM(first12h_flag) / COUNT(*) AS first12h_pct,
  SUM(final48h_flag) / COUNT(*) AS final48h_pct
FROM per_adm_class
GROUP BY class_label
ORDER BY class_label;