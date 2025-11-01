WITH ami_patients AS (
  SELECT DISTINCT 
    p.subject_id,
    d.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.seq_num = 1
    AND d.icd_code LIKE 'I21%'
    AND d.icd_version = 10  -- Focus on ICD-10 for modern AMI codes
),
initial_troponin AS (
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    le.valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM 
    ami_patients ap
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON ap.subject_id = le.subject_id AND ap.hadm_id = le.hadm_id
  WHERE 
    le.itemid IN (220229, 50924)  -- Troponin T (ng/mL and ng/ml)
    AND le.valuenum IS NOT NULL
    AND (le.valueuom = 'ng/mL' OR le.valueuom = 'ng/ml')
)
SELECT 
  CASE 
    WHEN valuenum < 0.01 THEN 'normal'
    WHEN valuenum >= 0.01 AND valuenum <= 0.1 THEN 'borderline'
    ELSE 'elevated'
  END AS troponin_category,
  COUNT(DISTINCT hadm_id) AS admission_count
FROM 
  initial_troponin
WHERE 
  rn = 1  -- Initial value only
GROUP BY 
  troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;