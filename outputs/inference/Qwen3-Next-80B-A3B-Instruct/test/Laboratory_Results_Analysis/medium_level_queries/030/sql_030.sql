WITH ami_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND LOWER(dicd.long_title) LIKE '%acute myocardial infarction%')
    )
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) IN (
    'high sensitivity troponin t',
    'hs-cTnT',
    'troponin t, high sensitivity',
    'troponin t high sensitivity'
  )
    AND l.valuenum IS NOT NULL
    AND l.valuenum >= 0
)
SELECT
  ROUND(100.0 * SUM(CASE WHEN ft.valuenum <= 0.014 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentage_normal,
  ROUND(100.0 * SUM(CASE WHEN ft.valuenum BETWEEN 0.015 AND 0.052 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentage_borderline,
  ROUND(100.0 * SUM(CASE WHEN ft.valuenum > 0.052 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentage_myocardial_injury
FROM ami_patients ap
INNER JOIN first_troponin ft
  ON ap.hadm_id = ft.hadm_id
WHERE ft.rn = 1;