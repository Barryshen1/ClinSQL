WITH 
-- Step 1: Identify the cohort
ami_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag 
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND d_diag.long_title LIKE '%Acute myocardial infarction%'
),

-- Step 2: Determine the index high-sensitivity troponin T measurement
troponin_t AS (
  SELECT a.hadm_id, 
         l.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) as rn
  FROM ami_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_l 
    ON l.itemid = d_l.itemid
  WHERE d_l.label LIKE '%Troponin T%'
    AND l.valuenum IS NOT NULL
),

-- Step 3: Categorize the index high-sensitivity troponin T measurement
troponin_t_category AS (
  SELECT hadm_id, 
         CASE 
           WHEN valuenum <= 0.014 THEN 'Normal'
           WHEN valuenum BETWEEN 0.015 AND 0.052 THEN 'Borderline'
           ELSE 'Myocardial Injury'
         END AS category
  FROM troponin_t
  WHERE rn = 1
)

-- Step 4: Calculate the percentage of patients in each category
SELECT category, 
       COUNT(*) as count,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM troponin_t_category), 2) as percentage
FROM troponin_t_category
GROUP BY category
ORDER BY category;