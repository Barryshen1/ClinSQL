SELECT
  MIN(le.valuenum) AS min_hemoglobin
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
JOIN
  physionet-data.mimiciv_3_1_hosp.labevents AS le
  ON adm.hadm_id = le.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_labitems AS dli
  ON le.itemid = dli.itemid
WHERE
  pat.gender = 'M'
  AND LOWER(ddx.long_title) LIKE '%ischemic stroke%'
  AND LOWER(dli.label) LIKE '%hemoglobin%'
  AND le.valuenum IS NOT NULL
  AND le.charttime IS NOT NULL
  AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 1 DAY);