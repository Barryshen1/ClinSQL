WITH ami_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
),
troponin_t_initial AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum >= 0
)
SELECT 
  CASE 
    WHEN tti.valuenum < 0.01 THEN 'normal'
    WHEN tti.valuenum < 0.10 THEN 'borderline'
    ELSE 'elevated'
  END AS troponin_category,
  COUNT(*) AS count
FROM ami_patients ap
INNER JOIN troponin_t_initial tti
  ON ap.hadm_id = tti.hadm_id
WHERE tti.rn = 1
GROUP BY troponin_category
ORDER BY troponin_category;