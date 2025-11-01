WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 35 AND 45
),
admissions_filtered AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
),
diagnoses_filtered AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM admissions_filtered)
  AND (dicd.long_title LIKE '%chest pain%' OR dicd.long_title LIKE '%myocardial infarction%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'R07.2')
),
first_troponin AS (
  SELECT l.hadm_id, l.valuenum, ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.hadm_id IN (SELECT hadm_id FROM diagnoses_filtered) AND l.itemid = 220651  
)
SELECT 
  CASE 
    WHEN valuenum < 0.014 THEN 'Normal'
    WHEN valuenum < 0.052 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS troponin_category,
  COUNT(*) as count
FROM first_troponin
WHERE rn = 1
GROUP BY troponin_category;