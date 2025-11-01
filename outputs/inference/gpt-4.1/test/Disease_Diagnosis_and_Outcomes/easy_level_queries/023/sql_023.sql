WITH pneumonia_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age,
    pat.gender,
    diag.icd_code,
    diag.icd_version,
    icd.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND diag.seq_num = 1
    AND (
      -- ICD-10 pneumonia codes J13-J18
      (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^J1[3-8]'))
      -- ICD-9 pneumonia codes 480-486
      OR (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^(480|481|482|483|484|485|486)'))
    )
    -- Community-acquired: likely emergency admission
    AND adm.admission_type = 'EMERGENCY'
    -- Valid times
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)

SELECT
  APPROX_QUANTILES(
    TIMESTAMP_DIFF(dischtime, admittime, DAY),
    2
  )[OFFSET(1)] AS median_hospital_los_days
FROM
  pneumonia_admissions;