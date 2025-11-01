WITH acs_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (dd.icd_code LIKE 'I21%' 
         OR dd.icd_code LIKE 'I22%' 
         OR dd.icd_code = 'I20.0')
),
first_troponin AS (
  SELECT 
    ap.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY le.charttime) AS rn
  FROM acs_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ap.hadm_id = le.hadm_id AND ap.subject_id = le.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.itemid = 51003  -- Troponin T
    AND le.valuenum IS NOT NULL
)
SELECT 
  CASE 
    WHEN valuenum < 0.01 THEN 'Normal'
    WHEN valuenum BETWEEN 0.01 AND 0.1 THEN 'Borderline'
    WHEN valuenum > 0.1 THEN 'Elevated'
  END AS category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM first_troponin
WHERE rn = 1
GROUP BY category
ORDER BY category;