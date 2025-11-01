SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile
FROM (
  SELECT
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    adm.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    adm.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
  ON
    dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
    AND dx.seq_num = 1
    AND (
      (ddx.icd_version = 9 AND ddx.icd_code BETWEEN '410' AND '414')
      OR
      (ddx.icd_version = 10 AND REGEXP_CONTAINS(ddx.icd_code, r'^I2[0-5]'))
    )
    AND adm.dischtime > adm.admittime
);