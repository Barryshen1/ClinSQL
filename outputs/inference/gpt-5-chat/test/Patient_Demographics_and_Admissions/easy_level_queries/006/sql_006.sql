WITH female_age AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
sepsis_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
cohort AS (
  SELECT DISTINCT sa.subject_id, sa.hadm_id
  FROM sepsis_admissions sa
  JOIN female_age fa
    ON sa.subject_id = fa.subject_id
)
SELECT
  PERCENTILE_CONT(los, 0.5) OVER() AS median_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
JOIN cohort c
  ON icu.subject_id = c.subject_id
 AND icu.hadm_id = c.hadm_id;