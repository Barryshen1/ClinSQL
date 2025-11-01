SELECT
  MIN(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS min_hospital_los_days
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
  ON dx.icd_code = ddx.icd_code
  AND dx.icd_version = ddx.icd_version
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 88 AND 98
  AND dx.seq_num = 1
  AND LOWER(ddx.long_title) LIKE '%community acquired pneumonia%'
  AND adm.admittime IS NOT NULL
  AND adm.dischtime IS NOT NULL;