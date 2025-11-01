WITH first_troponin AS (
  SELECT 
    p.subject_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY le.charttime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.labevents le
    ON p.subject_id = le.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(dl.label) LIKE '%troponin%'
    AND LOWER(dl.label) LIKE '%high%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
)
SELECT 
  CASE 
    WHEN valuenum < 0.014 THEN 'Normal'
    WHEN valuenum >= 0.014 AND valuenum < 0.04 THEN 'Borderline'
    WHEN valuenum >= 0.04 THEN 'Myocardial Injury'
  END AS troponin_category,
  COUNT(*) AS patient_count
FROM 
  first_troponin
WHERE 
  rn = 1
GROUP BY 
  troponin_category
ORDER BY 
  troponin_category;