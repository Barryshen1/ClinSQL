SELECT
  APPROX_QUANTILES(
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR), 100
  )[OFFSET(75)] AS percentile_75_hospital_los_hours
FROM
  physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
  ON adm.hadm_id = dx.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS ddx
  ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
WHERE
  dx.seq_num = 1
  AND ddx.icd_code = 'K922'
  AND ddx.icd_version = 10
  AND pat.gender = 'M'
  AND pat.anchor_age = 70;