WITH aki_primary_admissions AS (
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
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
      OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
    )
    AND adm.dischtime IS NOT NULL
    AND adm.admittime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(los, 0.75) OVER() AS los_75th_percentile_days
FROM
  aki_primary_admissions
;