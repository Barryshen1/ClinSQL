WITH 
t2_diag AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%' AND (icd_code LIKE '%0' OR icd_code LIKE '%2'))
    OR (icd_version = 10 AND icd_code LIKE 'E11%')
),
hf_diag AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%')
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hadm_id IN (SELECT hadm_id FROM t2_diag)
    AND a.hadm_id IN (SELECT hadm_id FROM hf_diag)
),
drug_classes AS (
  SELECT 'metformin' AS drug_class, r'metformin' AS pattern
  UNION ALL
  SELECT 'sulfonylureas', r'glipizide|glyburide|glimepiride'
  UNION ALL
  SELECT 'dpp4', r'sitagliptin|saxagliptin|linagliptin|alogliptin'
  UNION ALL
  SELECT 'sglt2', r'canagliflozin|dapagliflozin|empagliflozin'
),
prescription_flags AS (
  SELECT 
    c.hadm_id,
    dc.drug_class,
    MAX(CASE 
          WHEN p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) 
          THEN 1 ELSE 0 
        END) AS in_first_48h,
    MAX(CASE 
          WHEN p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime 
          THEN 1 ELSE 0 
        END) AS in_last_12h
  FROM cohort c
  CROSS JOIN drug_classes dc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND REGEXP_CONTAINS(LOWER(p.drug), dc.pattern)
  GROUP BY c.hadm_id, dc.drug_class
)
SELECT 
  drug_class,
  ROUND(AVG(in_first_48h) * 100, 2) AS prevalence_first_48h,
  ROUND(AVG(in_last_12h) * 100, 2) AS prevalence_last_12h,
  ROUND((AVG(in_last_12h) - AVG(in_first_48h)) * 100, 2) AS net_percentage_point_change
FROM prescription_flags
GROUP BY drug_class
ORDER BY drug_class;