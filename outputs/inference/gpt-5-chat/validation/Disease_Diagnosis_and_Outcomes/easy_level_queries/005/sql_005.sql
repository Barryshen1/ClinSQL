WITH ischemic_stroke_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND)/86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND (
         diag.icd_code LIKE '433%' OR
         diag.icd_code LIKE '434%' OR
         diag.icd_code LIKE '436%'
      ))
      OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
    )
)
SELECT
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days
FROM ischemic_stroke_admissions;