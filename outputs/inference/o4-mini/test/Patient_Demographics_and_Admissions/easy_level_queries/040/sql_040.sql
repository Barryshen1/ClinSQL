WITH female_35_45 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 35 AND 45
),
stroke_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%stroke%'
),
cohort_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN female_35_45 f
      ON icu.subject_id = f.subject_id
    JOIN stroke_admissions s
      ON icu.subject_id = s.subject_id
      AND icu.hadm_id = s.hadm_id
)
SELECT
  -- Approximate median ICU LOS (days) across all qualifying ICU stays
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los
FROM
  cohort_icu_stays;