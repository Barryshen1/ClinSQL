WITH FemaleCopdAdmissions AS (
  -- Step 1: Identify all hospital admissions (hadm_id) for female patients
  -- who were diagnosed with COPD during their stay.
  SELECT DISTINCT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON dx.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND (
      -- ICD-9 codes for COPD and related chronic airway obstructions
      dx.icd_code LIKE '491%' -- Chronic bronchitis
      OR dx.icd_code LIKE '492%' -- Emphysema
      OR dx.icd_code = '496' -- Chronic airway obstruction, NEC
      -- ICD-10 codes for COPD
      OR dx.icd_code LIKE 'J44%' -- Other chronic obstructive pulmonary disease
    )
)
-- Step 2: From the identified admissions, find all serum creatinine lab
-- results and calculate the overall maximum value.
SELECT
  MAX(le.valuenum) AS max_peak_serum_creatinine_mg_dl
FROM
  `physionet-data.mimiciv_3_1_hosp.labevents` AS le
INNER JOIN
  FemaleCopdAdmissions AS fca
  ON le.hadm_id = fca.hadm_id
WHERE
  -- ITEMID 50912 corresponds to 'Creatinine' in the blood
  le.itemid = 50912
  -- The question specifies the unit as mg/dL
  AND le.valueuom = 'mg/dL'
  -- Ensure we are only considering valid numeric measurements
  AND le.valuenum IS NOT NULL;