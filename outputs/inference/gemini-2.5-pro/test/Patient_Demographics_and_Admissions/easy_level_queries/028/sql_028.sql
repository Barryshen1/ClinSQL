WITH sepsis_admissions AS (
  -- First, find all hospital admissions (hadm_id) where a sepsis diagnosis was recorded.
  -- Using DISTINCT ensures each admission is counted only once, even if it has multiple sepsis codes.
  SELECT DISTINCT
    diag.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE
    LOWER(d_diag.long_title) LIKE '%sepsis%'
)
-- Now, calculate the standard deviation of ICU LOS for the specified cohort.
SELECT
  STDDEV(icu.los) AS stddev_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` AS icu
-- Join to filter for patients with sepsis
INNER JOIN
  sepsis_admissions
  ON icu.hadm_id = sepsis_admissions.hadm_id
-- Join to filter by patient demographics
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON icu.subject_id = pat.subject_id
WHERE
  -- Filter for male patients
  pat.gender = 'M'
  -- Filter for patients aged 90-100 at the time of their first admission
  AND pat.anchor_age BETWEEN 90 AND 100;