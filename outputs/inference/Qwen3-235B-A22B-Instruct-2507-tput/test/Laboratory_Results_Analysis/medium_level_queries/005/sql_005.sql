WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    -- Compute age at admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 35 AND 45
),
admissions_with_relevant_diagnosis AS (
  SELECT DISTINCT pa.hadm_id
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%chest pain%'
     OR LOWER(d.long_title) LIKE '%myocardial infarction%'
     OR LOWER(d.long_title) LIKE '%acute mi%'
),
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) = 'troponin t high sensitivity'
    AND le.valuenum IS NOT NULL
)
SELECT
  CASE
    WHEN ft.valuenum <= 14 THEN 'normal'
    WHEN ft.valuenum BETWEEN 15 AND 59 THEN 'borderline'
    WHEN ft.valuenum >= 60 THEN 'myocardial injury'
    ELSE 'unknown'
  END AS troponin_category,
  COUNT(*) AS count
FROM first_troponin ft
INNER JOIN admissions_with_relevant_diagnosis ad
  ON ft.hadm_id = ad.hadm_id
WHERE ft.rn = 1
GROUP BY troponin_category
ORDER BY troponin_category;