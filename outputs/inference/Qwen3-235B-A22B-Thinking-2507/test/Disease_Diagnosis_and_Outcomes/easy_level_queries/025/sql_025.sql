SELECT
  STDDEV(los_days) AS std_los
FROM (
  SELECT
    adm.hadm_id,
    EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age) AS age_at_admission,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
    AND adm.subject_id = diag.subject_id
  WHERE
    pat.gender = 'M'
    AND diag.seq_num = 1
    AND adm.dischtime IS NOT NULL
    AND (
      diag.icd_code LIKE 'K25.%'
      OR diag.icd_code LIKE 'K26.%'
      OR diag.icd_code LIKE 'K27.%'
      OR diag.icd_code LIKE 'K28.%'
      OR diag.icd_code = 'I85.0'
      OR diag.icd_code = 'I85.3'
      OR diag.icd_code = 'K92.0'
      OR diag.icd_code = 'K92.1'
    )
)
WHERE
  age_at_admission BETWEEN 77 AND 87;