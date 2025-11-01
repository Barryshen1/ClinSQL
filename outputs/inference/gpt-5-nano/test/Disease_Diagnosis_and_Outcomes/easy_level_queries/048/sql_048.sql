WITH septic_primary_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
   AND di.seq_num = 1  -- primary diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.dischtime IS NOT NULL
    AND (
      LOWER(dd.long_title) LIKE '%sepsis%'
      OR LOWER(dd.long_title) LIKE '%septic shock%'
      OR LOWER(dd.long_title) LIKE '%septicemia%'
    )
)
SELECT
  MAX(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS max_hospital_los_days
FROM septic_primary_admissions;