WITH ischemic_stroke_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  -- Only primary diagnosis
  WHERE
    diag.seq_num = 1
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
    -- Ischemic stroke ICD-10: I63.x
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
      OR
      -- Ischemic stroke ICD-9: 433.x1 or 434.x1 (with infarction)
      (diag.icd_version = 9 AND (
        diag.icd_code LIKE '433%1' OR diag.icd_code LIKE '434%1'
      ))
    )
    -- Valid LOS
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 0
)

SELECT
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS los_25th_percentile
FROM
  ischemic_stroke_admissions
;