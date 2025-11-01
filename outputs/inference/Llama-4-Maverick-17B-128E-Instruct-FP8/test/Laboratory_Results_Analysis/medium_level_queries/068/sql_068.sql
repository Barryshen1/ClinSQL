WITH patient_selection AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 42 AND 52
),
first_troponin AS (
  SELECT ps.subject_id,
         le.valuenum,
         ROW_NUMBER() OVER (PARTITION BY ps.subject_id ORDER BY le.charttime) as rn
  FROM patient_selection ps
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ps.subject_id = le.subject_id
  WHERE le.itemid = 50821  
    AND le.valuenum IS NOT NULL
)
SELECT 
  CASE
    WHEN valuenum < 0.014 THEN 'Normal'
    WHEN valuenum >= 0.014 AND valuenum < 0.04 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS troponin_category,
  COUNT(subject_id) AS patient_count
FROM first_troponin
WHERE rn = 1
GROUP BY 
  CASE
    WHEN valuenum < 0.014 THEN 'Normal'
    WHEN valuenum >= 0.014 AND valuenum < 0.04 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END
ORDER BY troponin_category;