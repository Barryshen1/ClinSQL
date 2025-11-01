WITH 
-- Filter patients based on age and gender
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 52 AND 62
),

-- Get hospital admissions for the filtered patients
admissions_for_filtered_patients AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE subject_id IN (SELECT subject_id FROM filtered_patients)
),

-- Identify procedures related to valve repair/replacement
valve_procedures AS (
  SELECT p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Replacement%' OR d.long_title LIKE '%Repair%' 
  AND d.long_title LIKE '%Valve%'
),

-- Calculate distinct valve repair/replacement procedures per hospitalization
procedures_per_hadm AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) as num_procedures
  FROM valve_procedures
  GROUP BY hadm_id
)

-- Calculate the interquartile range (IQR) of the count
SELECT 
  APPROX_QUANTILES(num_procedures, 100) AS quantiles,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS Q3,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] - APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS IQR
FROM procedures_per_hadm
WHERE hadm_id IN (SELECT hadm_id FROM admissions_for_filtered_patients);