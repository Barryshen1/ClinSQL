WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = a.hadm_id 
      AND (
        (di.icd_version = 9 AND di.icd_code LIKE '250%') 
        OR (di.icd_version = 10 AND (
          di.icd_code LIKE 'E08%' OR di.icd_code LIKE 'E09%' 
          OR di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' 
          OR di.icd_code LIKE 'E12%' OR di.icd_code LIKE 'E13%'
        ))
      )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` hf 
      WHERE hf.hadm_id = a.hadm_id 
      AND (
        (hf.icd_version = 9 AND hf.icd_code LIKE '428%') 
        OR (hf.icd_version = 10 AND hf.icd_code LIKE 'I50%')
      )
    )
),
total_cohort AS (
  SELECT COUNT(*) AS total FROM cohort
),
classes AS (
  SELECT med_class FROM UNNEST([
    'Insulin',
    'Biguanides',
    'Sulfonylureas',
    'DPP-4 Inhibitors',
    'SGLT2 Inhibitors',
    'GLP-1 Agonists',
    'Thiazolidinediones'
  ]) AS med_class
),
prescriptions_with_class AS (
  SELECT 
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Biguanides'
      WHEN LOWER(pr.drug) LIKE '%glipizide%' 
        OR LOWER(pr.drug) LIKE '%glyburide%' 
        OR LOWER(pr.drug) LIKE '%glimepiride%' 
        OR LOWER(pr.drug) LIKE '%tolbutamide%' THEN 'Sulfonylureas'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' 
        OR LOWER(pr.drug) LIKE '%saxagliptin%' 
        OR LOWER(pr.drug) LIKE '%linagliptin%' 
        OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
      WHEN LOWER(pr.drug) LIKE '%canagliflozin%' 
        OR LOWER(pr.drug) LIKE '%dapagliflozin%' 
        OR LOWER(pr.drug) LIKE '%empagliflozin%' 
        OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitors'
      WHEN LOWER(pr.drug) LIKE '%exenatide%' 
        OR LOWER(pr.drug) LIKE '%liraglutide%' 
        OR LOWER(pr.drug) LIKE '%dulaglutide%' 
        OR LOWER(pr.drug) LIKE '%albiglutide%' 
        OR LOWER(pr.drug) LIKE '%semaglutide%' 
        OR LOWER(pr.drug) LIKE '%tirzepatide%' THEN 'GLP-1 Agonists'
      WHEN LOWER(pr.drug) LIKE '%pioglitazone%' 
        OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      ELSE NULL
    END AS med_class
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE 
    pr.drug IS NOT NULL
),
first72_usage AS (
  SELECT DISTINCT 
    c.hadm_id,
    pwc.med_class
  FROM 
    cohort c
  JOIN 
    prescriptions_with_class pwc ON pwc.hadm_id = c.hadm_id 
      AND pwc.subject_id = c.subject_id
      AND pwc.med_class IS NOT NULL
  WHERE 
    pwc.starttime >= c.admittime
    AND pwc.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),
final24_usage AS (
  SELECT DISTINCT 
    c.hadm_id,
    pwc.med_class
  FROM 
    cohort c
  JOIN 
    prescriptions_with_class pwc ON pwc.hadm_id = c.hadm_id 
      AND pwc.subject_id = c.subject_id
      AND pwc.med_class IS NOT NULL
  WHERE 
    pwc.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
    AND pwc.starttime < c.dischtime
)
SELECT 
  'First 72h' AS period,
  cl.med_class,
  ROUND(COALESCE(COUNT(DISTINCT f.hadm_id), 0) * 100.0 / tc.total, 2) AS percentage
FROM 
  classes cl
CROSS JOIN 
  total_cohort tc
LEFT JOIN 
  first72_usage f ON f.med_class = cl.med_class
GROUP BY 
  cl.med_class, tc.total

UNION ALL

SELECT 
  'Final 24h' AS period,
  cl.med_class,
  ROUND(COALESCE(COUNT(DISTINCT l.hadm_id), 0) * 100.0 / tc.total, 2) AS percentage
FROM 
  classes cl
CROSS JOIN 
  total_cohort tc
LEFT JOIN 
  final24_usage l ON l.med_class = cl.med_class
GROUP BY 
  cl.med_class, tc.total
ORDER BY 
  period, med_class;