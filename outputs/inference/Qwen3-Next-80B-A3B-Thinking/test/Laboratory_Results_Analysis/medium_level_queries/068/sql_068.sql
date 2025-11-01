WITH first_troponin AS (
  SELECT
    le.subject_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE di.loinc_code = '4548-4'
    AND le.valueuom = 'ng/mL'
    AND le.valuenum IS NOT NULL
)
SELECT
  CASE
    WHEN ft.valuenum < 0.014 THEN 'Normal'
    WHEN ft.valuenum >= 0.014 AND ft.valuenum < 0.04 THEN 'Borderline'
    WHEN ft.valuenum >= 0.04 THEN 'Myocardial Injury'
  END AS troponin_category,
  COUNT(*) AS patient_count
FROM first_troponin ft
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ft.subject_id = p.subject_id
WHERE ft.rn = 1
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 42 AND 52
GROUP BY troponin_category;