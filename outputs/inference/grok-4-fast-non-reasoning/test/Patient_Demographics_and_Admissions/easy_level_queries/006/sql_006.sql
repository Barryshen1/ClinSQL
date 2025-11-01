WITH sepsis_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = SAFE_CAST(d.hadm_id AS INT64)
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND p.anchor_age > 0
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65%')
)
SELECT 
  PERCENTILE_CONT(icu_los_days, 0.5) AS median_icu_los_days
FROM (
  SELECT 
    i.stay_id,
    i.los / 24.0 AS icu_los_days
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    sepsis_admissions s
    ON i.subject_id = s.subject_id 
    AND i.hadm_id = s.hadm_id
  WHERE 
    i.los > 0
);