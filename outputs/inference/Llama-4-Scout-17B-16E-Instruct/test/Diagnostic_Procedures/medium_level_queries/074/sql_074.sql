WITH 
-- Identify ischemic stroke patients
ischemic_stroke_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.icd_code LIKE '433%'  -- Ischemic stroke ICD code
),

-- Identify imaging procedures
imaging_procedures AS (
  SELECT hadm_id, COUNT(*) as num_imaging_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_code LIKE '87%'  
  GROUP BY hadm_id
),

-- Calculate ICU stay duration
icu_stay_duration AS (
  SELECT subject_id, hadm_id, 
         DATE_DIFF(TIMESTAMP(icustays.outtime), TIMESTAMP(icustays.intime)) AS icu_stay_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)

-- Main query
SELECT 
  CASE 
    WHEN COALESCE(icu_stay_days, 0) BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN COALESCE(icu_stay_days, 0) BETWEEN 5 AND 7 THEN '5-7 days'
  END AS icu_stay_category,
  AVG(num_imaging_procedures) AS mean_imaging_procedures,
  MIN(num_imaging_procedures) AS min_imaging_procedures,
  MAX(num_imaging_procedures) AS max_imaging_procedures
FROM 
  ischemic_stroke_patients isp
  JOIN imaging_procedures ip 
    ON isp.hadm_id = ip.hadm_id
  LEFT JOIN icu_stay_duration icu 
    ON isp.hadm_id = icu.hadm_id
WHERE COALESCE(icu_stay_days, 0) BETWEEN 1 AND 7 OR icu_stay_days IS NULL
GROUP BY 
  CASE 
    WHEN COALESCE(icu_stay_days, 0) BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN COALESCE(icu_stay_days, 0) BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Outside range'
  END;