WITH cohort_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
    AND d.seq_num = 1  -- primary diagnosis
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND (
      -- ICD-9: 410-414 (ischemic heart disease / ACS)
      (d.icd_version = 9 AND SUBSTR(TRIM(d.icd_code), 1, 3) IN ('410','411','412','413','414'))
      OR
      -- ICD-10: I20-I25 (ischemic heart disease / ACS)
      (d.icd_version = 10 AND UPPER(SUBSTR(TRIM(d.icd_code), 1, 3)) IN ('I20','I21','I22','I23','I24','I25'))
    )
)
SELECT
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS avg_hospital_los_days
FROM
  cohort_admissions;