SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr
FROM (
  SELECT
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
    AND dx.seq_num = 1
    AND dx.icd_version = 10
    AND dx.icd_code IN ('A41.9', 'R65.20', 'R65.21')
    AND adm.dischtime IS NOT NULL
    AND adm.admittime IS NOT NULL
) AS los_data;