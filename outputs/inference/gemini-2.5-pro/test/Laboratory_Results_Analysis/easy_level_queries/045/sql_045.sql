WITH SepsisAdmissions AS (
  -- Step 1: Identify all hospital admissions (hadm_id) with a diagnosis of sepsis.
  SELECT DISTINCT dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    LOWER(d_dx.long_title) LIKE '%sepsis%'
),
MaleSepsisAdmissions AS (
  -- Step 2: Filter the sepsis admissions to include only male patients.
  -- Also, retrieve the hospital admission time to define the "admission" window.
  SELECT
    sa.hadm_id,
    adm.admittime
  FROM SepsisAdmissions AS sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON sa.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
)
-- Step 3 & 4: Find the maximum serum creatinine value measured within the
-- first 24 hours for this cohort.
SELECT
  MAX(le.valuenum) AS max_admission_creatinine
FROM MaleSepsisAdmissions AS msa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  ON msa.hadm_id = le.hadm_id
WHERE
  -- itemid 50912 corresponds to 'Creatinine' in the 'Blood' (serum)
  le.itemid = 50912
  -- Filter for lab events within the first 24 hours of hospital admission
  AND le.charttime BETWEEN msa.admittime AND DATETIME_ADD(msa.admittime, INTERVAL 24 HOUR)
  -- Ensure the value is a number
  AND le.valuenum IS NOT NULL;