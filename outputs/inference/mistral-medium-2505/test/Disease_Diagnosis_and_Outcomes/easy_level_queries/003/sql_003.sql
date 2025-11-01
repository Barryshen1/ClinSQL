WITH
-- Filter for female patients aged 40-50
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),

-- Get admissions with primary ischemic heart disease/ACS diagnosis
primary_acs_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN
    female_patients fp
    ON a.subject_id = fp.subject_id
  WHERE
    d.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-9 codes for ischemic heart disease/ACS
      (d.icd_version = 9 AND d.icd_code LIKE '410.%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '411.%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '412.%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '413.%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '414.%')
      -- ICD-10 codes for ischemic heart disease/ACS
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I20.%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I22.%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I23.%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I24.%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I25.%')
    )
    AND a.dischtime IS NOT NULL  -- Exclude missing discharge times
)

-- Calculate the 25th percentile LOS
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25_los
FROM
  primary_acs_admissions;