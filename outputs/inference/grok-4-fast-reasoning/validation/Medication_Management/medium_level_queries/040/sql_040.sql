WITH cohort AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime, p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
),
diag_diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND (
       icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR
       icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%'
     ))
),
diag_hf AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort_with_diag AS (
  SELECT c.hadm_id, c.admittime, c.dischtime, c.subject_id
  FROM cohort c
  INNER JOIN diag_diabetes dd ON c.hadm_id = dd.hadm_id
  INNER JOIN diag_hf dh ON c.hadm_id = dh.hadm_id
),
total_cohort AS (
  SELECT COUNT(*) AS total_adms
  FROM cohort_with_diag
),
classes AS (
  SELECT 'Insulin' AS drug_class UNION ALL
  SELECT 'Biguanide' UNION ALL
  SELECT 'Sulfonylurea' UNION ALL
  SELECT 'ACEI/ARB' UNION ALL
  SELECT 'Beta Blocker' UNION ALL
  SELECT 'Loop Diuretic' UNION ALL
  SELECT 'MRA' UNION ALL
  SELECT 'Digoxin'
),
first48_emar AS (
  SELECT
    e.hadm_id,
    CASE
      WHEN LOWER(e.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(e.medication) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(e.medication) LIKE '%glipizide%' OR
           LOWER(e.medication) LIKE '%glyburide%' OR
           LOWER(e.medication) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(e.medication) LIKE '%lisinopril%' OR
           LOWER(e.medication) LIKE '%enalapril%' OR
           LOWER(e.medication) LIKE '%ramipril%' OR
           LOWER(e.medication) LIKE '%captopril%' OR
           LOWER(e.medication) LIKE '%losartan%' OR
           LOWER(e.medication) LIKE '%valsartan%' OR
           LOWER(e.medication) LIKE '%candesartan%' THEN 'ACEI/ARB'
      WHEN LOWER(e.medication) LIKE '%metoprolol%' OR
           LOWER(e.medication) LIKE '%carvedilol%' OR
           LOWER(e.medication) LIKE '%bisoprolol%' OR
           LOWER(e.medication) LIKE '%atenolol%' OR
           LOWER(e.medication) LIKE '%propranolol%' THEN 'Beta Blocker'
      WHEN LOWER(e.medication) LIKE '%furosemide%' OR
           LOWER(e.medication) LIKE '%bumetanide%' OR
           LOWER(e.medication) LIKE '%torsemide%' THEN 'Loop Diuretic'
      WHEN LOWER(e.medication) LIKE '%spironolactone%' OR
           LOWER(e.medication) LIKE '%eplerenone%' THEN 'MRA'
      WHEN LOWER(e.medication) LIKE '%digoxin%' THEN 'Digoxin'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN cohort_with_diag c ON e.hadm_id = c.hadm_id
  WHERE e.charttime >= c.admittime
    AND e.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND e.medication IS NOT NULL
    AND LENGTH(e.medication) > 0
),
last12_emar AS (
  SELECT
    e.hadm_id,
    CASE
      WHEN LOWER(e.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(e.medication) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(e.medication) LIKE '%glipizide%' OR
           LOWER(e.medication) LIKE '%glyburide%' OR
           LOWER(e.medication) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(e.medication) LIKE '%lisinopril%' OR
           LOWER(e.medication) LIKE '%enalapril%' OR
           LOWER(e.medication) LIKE '%ramipril%' OR
           LOWER(e.medication) LIKE '%captopril%' OR
           LOWER(e.medication) LIKE '%losartan%' OR
           LOWER(e.medication) LIKE '%valsartan%' OR
           LOWER(e.medication) LIKE '%candesartan%' THEN 'ACEI/ARB'
      WHEN LOWER(e.medication) LIKE '%metoprolol%' OR
           LOWER(e.medication) LIKE '%carvedilol%' OR
           LOWER(e.medication) LIKE '%bisoprolol%' OR
           LOWER(e.medication) LIKE '%atenolol%' OR
           LOWER(e.medication) LIKE '%propranolol%' THEN 'Beta Blocker'
      WHEN LOWER(e.medication) LIKE '%furosemide%' OR
           LOWER(e.medication) LIKE '%bumetanide%' OR
           LOWER(e.medication) LIKE '%torsemide%' THEN 'Loop Diuretic'
      WHEN LOWER(e.medication) LIKE '%spironolactone%' OR
           LOWER(e.medication) LIKE '%eplerenone%' THEN 'MRA'
      WHEN LOWER(e.medication) LIKE '%digoxin%' THEN 'Digoxin'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN cohort_with_diag c ON e.hadm_id = c.hadm_id
  WHERE e.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND e.charttime < c.dischtime
    AND e.medication IS NOT NULL
    AND LENGTH(e.medication) > 0
),
first48_usage AS (
  SELECT drug_class, COUNT(DISTINCT hadm_id) AS num_used
  FROM first48_emar
  WHERE drug_class IS NOT NULL
  GROUP BY drug_class
),
last12_usage AS (
  SELECT drug_class, COUNT(DISTINCT hadm_id) AS num_used
  FROM last12_emar
  WHERE drug_class IS NOT NULL
  GROUP BY drug_class
)
SELECT
  cl.drug_class,
  ROUND(IFNULL(f.num_used, 0) * 100.0 / t.total_adms, 2) AS prev_first48_pct,
  ROUND(IFNULL(l.num_used, 0) * 100.0 / t.total_adms, 2) AS prev_last12_pct,
  ROUND(ABS(IFNULL(f.num_used, 0) * 100.0 / t.total_adms - IFNULL(l.num_used, 0) * 100.0 / t.total_adms), 2) AS abs_diff_pp
FROM classes cl
LEFT JOIN first48_usage f ON cl.drug_class = f.drug_class
LEFT JOIN last12_usage l ON cl.drug_class = l.drug_class
CROSS JOIN total_cohort t
ORDER BY cl.drug_class;