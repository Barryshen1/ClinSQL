WITH hf_admissions AS (
  SELECT DISTINCT dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    -- Use a case-insensitive search for "Heart Failure" to be robust.
    LOWER(d_dx.long_title) LIKE '%heart failure%'
)
-- Step 2: Find the maximum serum creatinine in the first 24h for these admissions.
SELECT
  MAX(le.valuenum) AS max_creatinine_first_24h
FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
-- Join with admissions to get admission time.
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON le.hadm_id = adm.hadm_id
-- Join with patients to filter by gender.
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON le.subject_id = pat.subject_id
-- Join with our HF admissions CTE to ensure the patient has heart failure.
INNER JOIN hf_admissions
  ON le.hadm_id = hf_admissions.hadm_id
WHERE
  -- Filter for Serum Creatinine (itemid 50912).
  le.itemid = 50912
  -- Filter for male patients.
  AND pat.gender = 'M'
  -- Filter for lab results within the first 24 hours of hospital admission.
  AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
  -- Ensure the value is a valid number.
  AND le.valuenum IS NOT NULL;