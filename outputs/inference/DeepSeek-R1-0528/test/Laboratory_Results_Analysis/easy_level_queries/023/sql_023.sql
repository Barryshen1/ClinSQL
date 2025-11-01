WITH sepsis_admissions AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE 
    -- ICD-9 codes for sepsis
    (diag.icd_version = 9 AND 
      (diag.icd_code LIKE '038%' OR diag.icd_code IN ('99591', '99592')))
    OR 
    -- ICD-10 codes for sepsis
    (diag.icd_version = 10 AND 
      (diag.icd_code LIKE 'A40%' OR diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R652%'))
),
male_sepsis_admissions AS (
  SELECT adm.hadm_id, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN sepsis_admissions sa 
    ON adm.hadm_id = sa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
),
discharge_lactate AS (
  SELECT lab.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN male_sepsis_admissions msa 
    ON lab.hadm_id = msa.hadm_id
  WHERE 
    lab.itemid = 50813  -- Serum lactate itemid
    AND DATE(lab.charttime) = DATE(msa.dischtime)  -- Measurement on discharge day
    AND lab.valuenum IS NOT NULL  -- Ensure numeric value
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr
FROM discharge_lactate;