WITH 
-- Identify ischemic stroke ICD codes
ischemic_stroke_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Ischemic stroke%' OR long_title LIKE '%Cerebral infarction%'
),

-- Filter patients and admissions
patients_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 84 AND 94
    AND p.gender = 'M'
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN (SELECT icd_code FROM ischemic_stroke_icd)
      GROUP BY hadm_id
      HAVING MIN(seq_num) = 1  -- Primary diagnosis
    )
)

-- Calculate maximum hospital LOS
SELECT 
  MAX(hospital_los) AS max_hospital_los
FROM 
  patients_admissions;