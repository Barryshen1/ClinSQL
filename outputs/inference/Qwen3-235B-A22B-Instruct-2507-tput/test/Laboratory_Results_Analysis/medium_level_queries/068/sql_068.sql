WITH troponin_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'troponin t high sensitive'
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN troponin_item ti ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
),
patient_troponin_first AS (
  SELECT ft.subject_id, ft.valuenum
  FROM first_troponin ft
  WHERE ft.rn = 1
),
aged_female_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
)
SELECT
  CASE
    WHEN pt.valuenum < 0.014 THEN 'Normal'
    WHEN pt.valuenum >= 0.014 AND pt.valuenum < 0.04 THEN 'Borderline'
    WHEN pt.valuenum >= 0.04 THEN 'Myocardial Injury'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS patient_count
FROM patient_troponin_first pt
INNER JOIN aged_female_patients afp ON pt.subject_id = afp.subject_id
GROUP BY troponin_category
ORDER BY troponin_category;