WITH sepsis_primary AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
    AND diag.seq_num = 1
    AND (
      -- ICD-9 codes for sepsis/septic shock
      (diag.icd_version = 9 AND (
        diag.icd_code LIKE '038%' OR
        diag.icd_code = '78552' OR
        diag.icd_code = '99591' OR
        diag.icd_code = '99592'
      ))
      OR
      -- ICD-10 codes for sepsis/septic shock
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'A40%' OR
        diag.icd_code LIKE 'A41%' OR
        diag.icd_code = 'R6520' OR
        diag.icd_code = 'R6521'
      ))
    )
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1_los_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3_los_days
FROM sepsis_primary;