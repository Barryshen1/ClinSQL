WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT DISTINCT a.hadm_id, a.admittime, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 66 AND 76
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN (
        '250.0', '250.00', '250.01', '250.02', '250.03', '250.1', '250.10', '250.11', '250.12', '250.13', 
        '250.2', '250.20', '250.21', '250.22', '250.23', '250.3', '250.30', '250.31', '250.32', '250.33', 
        '250.4', '250.40', '250.41', '250.42', '250.43', '250.5', '250.50', '250.51', '250.52', '250.53', 
        '250.6', '250.60', '250.61', '250.62', '250.63', '250.7', '250.70', '250.71', '250.72', '250.73', 
        '250.8', '250.80', '250.81', '250.82', '250.83', '250.9', '250.90', '250.91', '250.92', '250.93'
      )
      OR icd_code IN (
        '428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9', 
        '402.01', '402.11', '402.21', '404.01', '404.11', '404.21', '404.03', '404.13', '404.23'
      )
    )
    AND icu.outtime - icu.intime >= INTERVAL 3 DAY
),

-- Extract medication administration records for antidiabetic medications
antidiabetic_medication_events AS (
  SELECT 
    e.hadm_id,
    ed.charttime,
    di.label AS medication_name
  FROM 
    `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.emar` e ON ed.emar_id = e.emar_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON e.hadm_id = p.hadm_id AND e.poe_id = p.poe_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON LOWER(p.drug) = LOWER(di.label)
  WHERE 
    e.hadm_id IN (SELECT hadm_id FROM patients_of_interest)
    AND di.category = 'Medication'
    AND LOWER(di.label) LIKE '%antidiabetic%' 
)

-- Calculate percentages for each antidiabetic class in first 72h vs final 24h
first_72h_medications AS (
  SELECT 
    hadm_id,
    medication_name,
    charttime
  FROM 
    antidiabetic_medication_events
  WHERE 
    charttime BETWEEN (SELECT MIN(intime) FROM patients_of_interest) AND (SELECT MIN(intime) + INTERVAL 3 DAY FROM patients_of_interest)
),

last_24h_medications AS (
  SELECT 
    hadm_id,
    medication_name,
    charttime
  FROM 
    antidiabetic_medication_events
  WHERE 
    charttime BETWEEN (SELECT MAX(outtime) - INTERVAL 1 DAY FROM patients_of_interest) AND (SELECT MAX(outtime) FROM patients_of_interest)
)

SELECT 
  'First 72h' AS period,
  medication_name,
  COUNT(DISTINCT hadm_id) AS admissions_with_medication
FROM 
  first_72h_medications
GROUP BY 
  medication_name

UNION ALL

SELECT 
  'Last 24h' AS period,
  medication_name,
  COUNT(DISTINCT hadm_id) AS admissions_with_medication
FROM 
  last_24h_medications
GROUP BY 
  medication_name
;