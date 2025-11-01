SELECT
  APPROX_QUANTILES(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR), 100)[OFFSET(25)] AS los_25th_percentile_hours
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
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 50 AND 60
  AND dx.seq_num = 1
  AND (
    (dx.icd_version = 9 AND dx.icd_code = '43491')
    OR
    (dx.icd_version = 10 AND dx.icd_code = 'I639')
    OR
    LOWER(ddx.long_title) LIKE '%ischemic stroke%'
  );