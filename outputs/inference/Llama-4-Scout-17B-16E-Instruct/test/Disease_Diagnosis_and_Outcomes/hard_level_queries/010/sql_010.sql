WITH 
  -- Identify DKA patients
  dka_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 39 AND 49
      AND d.icd_code IN ('250.1', '250.11', '250.12', '250.13', '250.14', '250.15', '250.16', '250.17', '250.18', '250.19')  -- ICD-9 codes for DKA
  ),
  
  -- Calculate 30-day mortality and risk score
  patient_outcomes AS (
    SELECT 
      a.subject_id, 
      a.hadm_id,
      CASE 
        WHEN a.hospital_expire_flag = 1 THEN 1 
        ELSE 0 
      END AS hospital_death,
      TIMESTAMP_DIFF(COALESCE(a.deathtime, a.dischtime), a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  ),
  
  -- Identify complications
  complications AS (
    SELECT 
      a.hadm_id,
      CASE 
        WHEN d.icd_code IN ('410', '410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9') THEN 'Cardiovascular'
        WHEN d.icd_code IN ('430', '431', '432', '433', '434', '435', '436', '437', '438') THEN 'Neurologic'
        ELSE NULL
      END AS complication_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  )

SELECT 
  -- DKA vs all males
  'DKA' AS patient_group,
  AVG(p.hospital_death) AS mean_30_day_mortality,
  AVG(p.los) AS mean_survivor_los
FROM 
  patient_outcomes p
  JOIN dka_patients d ON p.hadm_id = d.hadm_id

UNION ALL

SELECT 
  'All Males' AS patient_group,
  AVG(p.hospital_death) AS mean_30_day_mortality,
  AVG(p.los) AS mean_survivor_los
FROM 
  patient_outcomes p
WHERE 
  p.subject_id IN (
    SELECT 
      subject_id 
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` 
    WHERE 
      gender = 'M' 
      AND anchor_age BETWEEN 39 AND 49
  )

-- Complication rates
UNION ALL

SELECT 
  'DKA' AS patient_group,
  c.complication_type,
  COUNT(c.complication_type) / COUNT(DISTINCT c.hadm_id) AS complication_rate
FROM 
  complications c
  JOIN dka_patients d ON c.hadm_id = d.hadm_id
GROUP BY 
  c.complication_type

UNION ALL

SELECT 
  'All Males' AS patient_group,
  c.complication_type,
  COUNT(c.complication_type) / COUNT(DISTINCT c.hadm_id) AS complication_rate
FROM 
  complications c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt ON a.subject_id = pt.subject_id
WHERE 
  pt.gender = 'M' 
  AND pt.anchor_age BETWEEN 39 AND 49
GROUP BY 
  c.complication_type;