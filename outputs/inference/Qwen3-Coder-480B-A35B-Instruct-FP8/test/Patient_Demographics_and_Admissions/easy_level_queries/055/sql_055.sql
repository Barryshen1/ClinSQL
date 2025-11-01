SELECT
  APPROX_QUANTILES(los_days, 4)[ORDINAL(2)] AS percentile_25th_los_days
FROM (
  SELECT DISTINCT
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients pat
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
  ON
    pat.subject_id = adm.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  ON
    adm.hadm_id = diag.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag
  ON
    diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
);