WITH 
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 58 AND 68
  AND a.hadm_id IN (
    SELECT hadm_id 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_code IN ('E11.01', 'E11.69')  -- Example ICD codes, actual codes for HHS should be used
  )
),
admissions_los AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    icu.intime,
    icu.outtime,
    DATETIME_DIFF(icu.outtime, icu.intime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM eligible_patients)
),
radiography_ct_procedures AS (
  SELECT 
    pe.hadm_id,
    COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%Radiography%' OR di.label LIKE '%CT%'
  GROUP BY pe.hadm_id
)
SELECT 
  CASE 
    WHEN a.los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN a.los BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Other'
  END AS los_category,
  COUNT(DISTINCT a.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(r.num_procedures) AS mean_radiography_ct_procedures
FROM admissions_los a
LEFT JOIN radiography_ct_procedures r ON a.hadm_id = r.hadm_id
WHERE a.los BETWEEN 1 AND 7
GROUP BY los_category
ORDER BY los_category;