WITH hf_admissions AS (
  -- First, identify the cohort of hospital admissions for 65-year-old male patients with heart failure.
  SELECT DISTINCT -- Use DISTINCT to avoid processing the same admission multiple times
    adm.hadm_id,
    adm.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    -- Filter for male patients
    pat.gender = 'M'
    -- Filter for patients who were 65 at the time of admission
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age = 65
    -- Filter for heart failure diagnoses (case-insensitive)
    AND LOWER(d_dx.long_title) LIKE '%heart failure%'
)
-- Then, find the minimum serum sodium from this cohort's admission labs.
SELECT
  MIN(le.valuenum) AS min_admission_serum_sodium
FROM
  hf_admissions AS hf_adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  ON hf_adm.hadm_id = le.hadm_id
WHERE
  -- Filter for Serum Sodium (itemid 50983)
  le.itemid = 50983
  -- Filter for lab results within the first 24 hours of hospital admission
  AND le.charttime BETWEEN hf_adm.admittime AND DATETIME_ADD(hf_adm.admittime, INTERVAL 24 HOUR)
  -- Ensure the value is a number to be used in the MIN() function
  AND le.valuenum IS NOT NULL;