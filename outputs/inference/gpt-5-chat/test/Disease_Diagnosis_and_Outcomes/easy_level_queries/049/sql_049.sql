WITH stroke_patients AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND (
        diag.icd_code LIKE '433%' OR
        diag.icd_code LIKE '434%' OR
        diag.icd_code LIKE '436%'
      ))
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
    )
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS los_25th_percentile
FROM stroke_patients;