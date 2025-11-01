WITH 
-- Identify first admissions
first_admissions AS (
  SELECT subject_id, MIN(hadm_id) AS first_hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY subject_id
),

-- Filter patients by age and gender
filtered_patients AS (
  SELECT a.subject_id, a.hadm_id, 
         TIMESTAMP_DIFF(a.dischtime, a.admittime, 'DAY') AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  JOIN first_admissions fa
  ON a.hadm_id = fa.first_hadm_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 52 AND 62
),

-- Identify patients who received anticoagulants
anticoagulant_patients AS (
  SELECT DISTINCT p.hadm_id
  FROM filtered_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  ON p.hadm_id = pi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
  WHERE dp.long_title LIKE '%Anticoagulant%'
)

SELECT 
  STDEV(fp.los_days) AS sd_los
FROM 
  filtered_patients fp
WHERE 
  fp.hadm_id IN (SELECT hadm_id FROM anticoagulant_patients);