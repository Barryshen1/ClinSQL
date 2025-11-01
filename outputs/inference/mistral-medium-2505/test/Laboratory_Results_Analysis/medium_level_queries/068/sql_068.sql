WITH female_patients_42_52 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 42 AND 52
),

first_troponin AS (
  SELECT
    p.subject_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY le.charttime) AS rn
  FROM
    female_patients_42_52 p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    p.subject_id = le.subject_id
  WHERE
    le.itemid = 51006  -- hs-Troponin T
    AND le.valuenum IS NOT NULL
)

SELECT
  CASE
    WHEN ft.valuenum < 0.014 THEN 'Normal (<0.014 ng/mL)'
    WHEN ft.valuenum >= 0.014 AND ft.valuenum < 0.04 THEN 'Borderline (0.014–<0.04)'
    WHEN ft.valuenum >= 0.04 THEN 'Myocardial Injury (≥0.04)'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(DISTINCT ft.subject_id) AS patient_count
FROM
  first_troponin ft
WHERE
  ft.rn = 1  -- Only the first measurement per patient
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal (<0.014 ng/mL)' THEN 1
    WHEN 'Borderline (0.014–<0.04)' THEN 2
    WHEN 'Myocardial Injury (≥0.04)' THEN 3
    ELSE 4
  END;