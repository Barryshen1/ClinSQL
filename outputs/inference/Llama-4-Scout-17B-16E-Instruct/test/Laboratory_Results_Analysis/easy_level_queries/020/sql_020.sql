WITH 
-- Identify patients of interest (male, heart failure)
heart_failure_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M' AND dd.long_title LIKE '%Heart failure%'
),

-- Find nadir hemoglobin for each patient
nadir_hemoglobin AS (
  SELECT 
    hfp.hadm_id,
    MIN(CASE 
          WHEN dli.label = 'Hemoglobin' AND le.valuenum IS NOT NULL THEN le.valuenum
          ELSE NULL 
        END) AS nadir_hemoglobin
  FROM heart_failure_patients hfp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON hfp.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  GROUP BY hfp.hadm_id
)

-- Calculate 75th percentile of nadir hemoglobin
SELECT 
  APPROX_QUANTILES(nadir_hemoglobin, 100)[OFFSET(75)] AS percentile_75
FROM (
  SELECT nadir_hemoglobin 
  FROM nadir_hemoglobin 
  WHERE nadir_hemoglobin IS NOT NULL
);