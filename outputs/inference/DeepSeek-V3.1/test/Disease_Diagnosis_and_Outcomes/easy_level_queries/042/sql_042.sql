SELECT
  AVG(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS avg_los
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
ON
  adm.subject_id = pat.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
ON
  adm.subject_id = diag.subject_id
  AND adm.hadm_id = diag.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
ON
  diag.icd_code = dicd.icd_code
  AND diag.icd_version = dicd.icd_version
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 78 AND 88
  AND diag.seq_num = 1
  AND dicd.icd_code LIKE 'I2%'
  AND diag.icd_version = 10;