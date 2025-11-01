WITH first_troponin AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON 
    a.subject_id = le.subject_id 
    AND a.hadm_id = le.hadm_id
    AND le.itemid = 5352  -- hs-Troponin T
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.charttime IS NOT NULL
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY le.charttime ASC) = 1
)
SELECT 
  CASE 
    WHEN valuenum < 0.014 THEN 'Normal (<0.014 ng/mL)'
    WHEN valuenum < 0.04 THEN 'Borderline (0.014–<0.04)'
    ELSE 'Myocardial Injury (≥0.04)'
  END AS troponin_category,
  COUNT(DISTINCT subject_id) AS patient_count
FROM 
  first_troponin
GROUP BY 
  troponin_category
ORDER BY 
  MIN(valuenum);  -- Orders categories naturally: Normal, Borderline, Injury;