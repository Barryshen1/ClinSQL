WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime,
    -- Calculate age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pt.gender = 'F'
    AND diag.seq_num = 1  -- Primary diagnosis
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%') 
      OR 
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
      OR 
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I22%')
    )
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE admission_age BETWEEN 64 AND 74
),
troponin AS (
  SELECT 
    fc.subject_id,
    fc.hadm_id,
    le.valuenum
  FROM filtered_cohort fc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fc.hadm_id = le.hadm_id
  WHERE 
    le.itemid = 51006  -- High-sensitivity troponin T
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),
categorized AS (
  SELECT 
    *,
    CASE 
      WHEN valuenum <= 0.014 THEN 'Normal'
      WHEN valuenum <= 0.052 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS category
  FROM troponin
)
SELECT 
  category,
  COUNT(*) AS num_admissions,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS percentage
FROM categorized
GROUP BY category
ORDER BY category;