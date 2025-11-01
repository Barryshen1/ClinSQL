WITH patient_age AS (
  SELECT p.subject_id, a.hadm_id, p.gender, 
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
),
acute_pancreatitis_patients AS (
  SELECT DISTINCT a.hadm_id
  FROM patient_age a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE a.gender = 'M' AND a.age BETWEEN 42 AND 52
  AND dicd.long_title LIKE '%Acute pancreatitis%'
),
los_data AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         COUNT(pi.icd_code) AS num_procedures
  FROM acute_pancreatitis_patients app
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON app.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON a.hadm_id = pi.hadm_id
  GROUP BY a.hadm_id, a.admittime, a.dischtime
),
los_categories AS (
  SELECT hadm_id, num_procedures,
         CASE 
           WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
           WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
           ELSE 'Outside range'
         END AS los_category
  FROM los_data
)
SELECT 
  los_category,
  COUNT(hadm_id) AS patient_count,
  AVG(num_procedures) AS mean_procedures,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures
FROM los_categories
WHERE los_category != 'Outside range'
GROUP BY los_category
ORDER BY los_category;