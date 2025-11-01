WITH male_90_100 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 90 AND 100
),
sepsis_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    -- ICD-10 sepsis codes
    (d.icd_version = 10 AND (dd.icd_code LIKE 'A40%' OR dd.icd_code LIKE 'A41%'))
    -- ICD-9 sepsis codes
    OR (d.icd_version = 9 AND (dd.icd_code IN ('99591', '99592', '78552')))
  )
),
target_icustays AS (
  SELECT icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN male_90_100 p ON icu.subject_id = p.subject_id
  JOIN sepsis_admissions s ON icu.subject_id = s.subject_id AND icu.hadm_id = s.hadm_id
)
SELECT
  STDDEV_SAMP(los) AS icu_los_stddev_days
FROM target_icustays;