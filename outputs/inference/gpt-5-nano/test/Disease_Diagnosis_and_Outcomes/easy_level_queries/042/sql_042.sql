WITH ischemic_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- LOS in days (fractional) using DATETIME_DIFF to avoid UNIX_SECONDS on DATETIME
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  WHERE
    -- Female patients
    UPPER(p.gender) = 'F'
    -- Age at admission between 78 and 88
    AND (p.anchor_age IS NOT NULL AND p.anchor_year IS NOT NULL)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 78 AND 88
    -- Primary diagnosis (seq_num = 1)
    AND di.seq_num = 1
    -- Ischemic heart disease / ACS ICD codes (ICD-9 and ICD-10)
    AND (
      (di.icd_version = 9 AND (
          di.icd_code LIKE '410%' OR
          di.icd_code LIKE '411%' OR
          di.icd_code LIKE '412%' OR
          di.icd_code LIKE '413%' OR
          di.icd_code LIKE '414%'
      ))
      OR
      (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^I2[0-5]'))
    )
)

SELECT
  AVG(los_days) AS avg_hosp_los_days
FROM ischemic_admissions;