SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS los_25th_percentile
FROM (
  SELECT
    CAST(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) AS FLOAT64) / 24.0 AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON adm.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 67 AND 77
    AND diag.seq_num = 1
    AND diag.icd_version = 10
    AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
) AS los_subquery
LIMIT 1;