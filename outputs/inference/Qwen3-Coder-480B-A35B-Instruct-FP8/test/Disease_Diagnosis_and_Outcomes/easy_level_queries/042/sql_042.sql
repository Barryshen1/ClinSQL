SELECT
  AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS avg_hospital_los
FROM
  physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
  ON adm.hadm_id = dx.hadm_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 78 AND 88
  AND dx.seq_num = 1
  AND dx.icd_version = 10
  AND (
    dx.icd_code LIKE 'I20%'
    OR dx.icd_code LIKE 'I21%'
    OR dx.icd_code LIKE 'I22%'
    OR dx.icd_code LIKE 'I23%'
    OR dx.icd_code LIKE 'I24%'
    OR dx.icd_code LIKE 'I25%'
  )
  AND adm.dischtime IS NOT NULL
  AND adm.admittime IS NOT NULL;