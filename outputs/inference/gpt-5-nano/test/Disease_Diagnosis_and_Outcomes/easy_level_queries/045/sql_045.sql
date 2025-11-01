WITH admissions_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
diag_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE WHEN LOWER(ld.long_title) LIKE '%copd%' OR LOWER(ld.long_title) LIKE '%chronic obstructive pulmonary disease%' THEN 1 ELSE 0 END) AS has_copd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ld
    ON di.icd_code = ld.icd_code
   AND di.icd_version = ld.icd_version
  GROUP BY di.subject_id, di.hadm_id
),
cohort AS (
  SELECT ac.subject_id, ac.hadm_id, ac.los_days
  FROM admissions_cohort AS ac
  JOIN diag_flags AS df
    ON ac.subject_id = df.subject_id
   AND ac.hadm_id = df.hadm_id
  WHERE df.has_hf = 1
    AND df.has_copd = 1
)
SELECT STDDEV_SAMP(los_days) AS stddev_hospital_los_days
FROM cohort;