WITH ugib_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
    AND adm.subject_id = diag.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND (
         diag.icd_code LIKE '578%' OR
         diag.icd_code LIKE '531%' OR
         diag.icd_code LIKE '532%' OR
         diag.icd_code LIKE '533%' OR
         diag.icd_code LIKE '534%' OR
         diag.icd_code LIKE '535%'
       ))
      OR
      (diag.icd_version = 10 AND (
         diag.icd_code LIKE 'K25%' OR
         diag.icd_code LIKE 'K26%' OR
         diag.icd_code LIKE 'K27%' OR
         diag.icd_code LIKE 'K28%' OR
         diag.icd_code LIKE 'K92%'
       ))
    )
)
SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_los_days
FROM (
  SELECT
    APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM ugib_admissions
)
;