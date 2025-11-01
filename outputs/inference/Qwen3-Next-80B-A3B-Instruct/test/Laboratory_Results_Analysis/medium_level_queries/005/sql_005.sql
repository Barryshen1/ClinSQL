WITH first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%troponin%' 
    AND LOWER(d.label) LIKE '%high%' 
    AND LOWER(d.label) LIKE '%t%'
    AND l.valuenum IS NOT NULL
),
eligible_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND (
      LOWER(di.long_title) LIKE '%chest pain%'
      OR LOWER(di.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(di.long_title) LIKE '%myocardial infarction%'
      OR d.icd_code LIKE '410%'  -- ICD-9 AMI
      OR d.icd_code LIKE 'I21%'  -- ICD-10 AMI
      OR d.icd_code LIKE 'I22%'  -- ICD-10 AMI
      OR d.icd_code = 'R07.9'   -- Chest pain, unspecified
      OR d.icd_code = 'R07.89'  -- Other chest pain
    )
)
SELECT
  CASE 
    WHEN ft.valuenum <= 14 THEN 'Normal'
    WHEN ft.valuenum > 14 AND ft.valuenum <= 50 THEN 'Borderline'
    WHEN ft.valuenum > 50 THEN 'Myocardial injury'
  END AS troponin_category,
  COUNT(*) AS count
FROM first_troponin ft
JOIN eligible_admissions ea
  ON ft.hadm_id = ea.hadm_id
WHERE ft.rn = 1
GROUP BY troponin_category
ORDER BY troponin_category;