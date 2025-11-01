WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
    AND di.seq_num = 1                                  -- primary diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
    ON di.icd_code = dicd.icd_code
    AND di.icd_version = dicd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.dischtime IS NOT NULL
    AND (
      LOWER(dicd.long_title) LIKE '%sepsis%'   -- covers "sepsis"
      OR LOWER(dicd.long_title) LIKE '%septic%' -- covers "septic shock", etc.
    )
)

SELECT
  subject_id,
  hadm_id,
  ROUND(los_days, 2) AS hosp_los_days
FROM cohort_admissions
ORDER BY hosp_los_days DESC
LIMIT 1;