SELECT
  STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS los_sd
FROM
  physionet-data.mimiciv_3_1_hosp.patients pat
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag
  ON diag.icd_code = d_diag.icd_code
  AND diag.icd_version = d_diag.icd_version
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 45 AND 55
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code IN ('431', '432'))
    OR
    (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^I61|^I62'))
  );