WITH stroke_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND dx.seq_num = 1
    AND (
      (dx.icd_version = 10 AND dx.icd_code LIKE 'I63%')
      OR (dx.icd_version = 9 AND (dx.icd_code LIKE '433%' OR dx.icd_code LIKE '434%'))
    )
)
SELECT
  MAX(los_days) AS max_hosp_los_days
FROM
  stroke_admissions;