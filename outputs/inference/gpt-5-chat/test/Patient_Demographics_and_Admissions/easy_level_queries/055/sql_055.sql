WITH pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  /* pneumonia ICD-9: 480-486, ICD-10: J12-J18 */
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND (
      (diag.icd_version = 9 AND diag.icd_code BETWEEN '480' AND '486')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J12%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J13%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J14%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J15%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J16%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J17%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J18%')
    )
)
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS p25_los_days
FROM pneumonia_admissions;