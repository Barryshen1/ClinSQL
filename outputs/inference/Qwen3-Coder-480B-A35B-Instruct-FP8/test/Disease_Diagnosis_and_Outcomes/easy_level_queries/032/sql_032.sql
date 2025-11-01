SELECT
  APPROX_QUANTILES(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR), 4)[OFFSET(3)] -
  APPROX_QUANTILES(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR), 4)[OFFSET(1)] AS iqr_los_hours
FROM
  physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
  ON adm.hadm_id = dx.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS ddx
  ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 81 AND 91
  AND dx.seq_num = 1
  AND LOWER(ddx.long_title) LIKE '%acute kidney injury%';