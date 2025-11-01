WITH sepsis_admissions AS (
  -- Admissions of females age 58–68 with a sepsis diagnosis
  SELECT DISTINCT
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id
   AND a.hadm_id     = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
    ON d.icd_code    = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND LOWER(dicd.long_title) LIKE '%sepsis%'
),

icu_encounters AS (
  -- All ICU stays for the sepsis admissions
  SELECT
    stay_id    AS icustay_id,
    hadm_id    AS icu_hadm_id,
    los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
)

-- Compute the median ICU LOS
SELECT
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los_days
FROM icu_encounters;