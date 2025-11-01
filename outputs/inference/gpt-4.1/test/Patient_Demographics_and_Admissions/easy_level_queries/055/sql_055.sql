WITH pneumonia_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND (
      -- ICD-10 pneumonia: J12-J18
      (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^J1[2-8]'))
      -- ICD-9 pneumonia: 480-486 (string match, not cast)
      OR (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^(480|481|482|483|484|485|486)'))
    )
)

SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER () AS los_25th_percentile_days
FROM (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    pneumonia_admissions
  WHERE
    admittime IS NOT NULL
    AND dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(dischtime, admittime, DAY) > 0
);