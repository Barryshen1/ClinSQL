WITH cohort AS (
  SELECT DISTINCT ad.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON p.subject_id = ad.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND di.seq_num = 1
    AND (
      (di.icd_version = '9' AND (di.icd_code LIKE '410.%' OR di.icd_code = '411.1'))
      OR
      (di.icd_version = '10' AND (di.icd_code LIKE 'I21.%' OR di.icd_code = 'I20.0'))
    )
),
initial_trop AS (
  SELECT 
    le.hadm_id, 
    le.valuenum, 
    le.value,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c ON le.hadm_id = c.hadm_id
  WHERE le.itemid = 50586
    AND le.valueuom = 'ng/mL'
    AND (le.valuenum IS NOT NULL OR le.value IS NOT NULL)
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM (
  SELECT 
    hadm_id,
    CASE 
      WHEN valuenum IS NOT NULL AND valuenum < 0.01 THEN 'Normal'
      WHEN valuenum IS NULL AND value LIKE '<0.01%' THEN 'Normal'
      WHEN valuenum IS NOT NULL AND valuenum >= 0.01 AND valuenum < 0.1 THEN 'Borderline'
      WHEN valuenum IS NOT NULL AND valuenum >= 0.1 THEN 'Elevated'
      ELSE NULL  -- Exclude invalid cases
    END AS category
  FROM initial_trop
  WHERE rn = 1
    AND (
      (valuenum IS NOT NULL AND valuenum >= 0)  -- Non-negative numerics
      OR (valuenum IS NULL AND value LIKE '<0.01%')  -- Below-detection
    )
)
WHERE category IS NOT NULL
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'Normal' THEN 1 
    WHEN 'Borderline' THEN 2 
    WHEN 'Elevated' THEN 3 
  END
;