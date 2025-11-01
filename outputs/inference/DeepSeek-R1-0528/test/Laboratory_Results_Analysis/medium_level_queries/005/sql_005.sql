WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 35 AND 45
),
chest_pain_ami_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code = '786.5')) 
    OR 
    (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code = 'R07.4'))
),
cohort_dx AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN chest_pain_ami_admissions d
    ON c.hadm_id = d.hadm_id
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort_dx c
    ON l.hadm_id = c.hadm_id
  WHERE 
    l.itemid = 51006  -- High-sensitivity troponin T
    AND l.valuenum IS NOT NULL
),
categorized_troponin AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN valuenum <= 14 THEN 'Normal'
      WHEN valuenum > 14 AND valuenum <= 20 THEN 'Borderline'
      WHEN valuenum > 20 THEN 'Myocardial injury'
    END AS category
  FROM first_troponin
  WHERE rn = 1  -- First troponin test per admission
)
SELECT 
  category,
  COUNT(*) AS count
FROM categorized_troponin
GROUP BY category
ORDER BY category;