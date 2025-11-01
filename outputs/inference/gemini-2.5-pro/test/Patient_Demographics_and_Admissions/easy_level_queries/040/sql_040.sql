WITH stroke_admissions AS (
  -- First, find all hospital admissions (hadm_id) with a stroke diagnosis.
  -- Use DISTINCT to avoid duplicating admissions that have multiple stroke-related codes.
  SELECT DISTINCT dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE
    LOWER(ddx.long_title) LIKE '%stroke%'
),
target_patients AS (
  -- Second, identify the patient cohort: females aged 35-45.
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 35 AND 45
)
-- Finally, join ICU stays with the two cohorts and calculate the median LOS.
SELECT
  APPROX_QUANTILES(icu.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
-- Join to ensure the ICU stay belongs to a hospital admission for stroke.
INNER JOIN stroke_admissions AS sa
  ON icu.hadm_id = sa.hadm_id
-- Join to ensure the patient is in the target demographic.
INNER JOIN target_patients AS tp
  ON icu.subject_id = tp.subject_id;