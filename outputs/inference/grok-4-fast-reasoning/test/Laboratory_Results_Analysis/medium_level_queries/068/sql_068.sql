WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 42 AND 52
),
first_troponin AS (
  SELECT 
    le.subject_id,
    le.valuenum,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN filtered_patients fp 
    ON le.subject_id = fp.subject_id
  WHERE le.itemid = 50314
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY le.subject_id 
    ORDER BY le.charttime ASC
  ) = 1
)
SELECT 
  CASE 
    WHEN valuenum < 0.014 THEN 'Normal (<0.014 ng/mL)'
    WHEN valuenum < 0.04 THEN 'Borderline (0.014–<0.04)'
    ELSE 'Myocardial Injury (≥0.04)'
  END AS category,
  COUNT(*) AS patient_count
FROM first_troponin
GROUP BY category
ORDER BY category;