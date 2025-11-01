WITH dka_hhs_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 10 AND icd_code IN (
      'E10.10', 'E10.11', 'E11.10', 'E11.11', 'E13.10', 'E13.11',  -- DKA
      'E10.02', 'E11.02', 'E13.02'                                   -- HHS
    ))
    OR
    (icd_version = 9 AND SUBSTR(icd_code, 1, 4) = '250.' AND (
      SUBSTR(icd_code, 5, 1) = '1' OR  -- DKA: 250.1x
      SUBSTR(icd_code, 5, 2) = '02'   -- HHS: 250.02
    ))
  )
),
filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN dka_hhs_codes
    ON diag.icd_code = dka_hhs_codes.icd_code
    AND diag.icd_version = dka_hhs_codes.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND diag.seq_num = 1  -- Primary diagnosis
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
)
SELECT
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS hospital_los_25th_percentile
FROM filtered_admissions;