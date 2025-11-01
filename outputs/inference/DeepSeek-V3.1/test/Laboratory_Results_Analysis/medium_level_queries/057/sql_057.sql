WITH acs_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (dd.icd_code LIKE 'I20.0%' 
         OR dd.icd_code LIKE 'I21%' 
         OR dd.icd_code LIKE 'I22%')
),
first_troponin AS (
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY le.charttime) AS rn
  FROM acs_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ap.hadm_id = le.hadm_id
  WHERE le.itemid = 51003  -- Troponin T
    AND le.valuenum IS NOT NULL
)
SELECT 
  CASE 
    WHEN troponin_value <= 0.04 THEN 'Normal (≤0.04)'
    WHEN troponin_value > 0.04 AND troponin_value <= 0.1 THEN 'Borderline (>0.04–0.1)'
    WHEN troponin_value > 0.1 THEN 'Elevated (>0.1)'
  END AS troponin_category,
  COUNT(*) AS admission_count
FROM first_troponin
WHERE rn = 1  -- Only the first troponin measurement per admission
GROUP BY troponin_category
ORDER BY troponin_category;