SELECT
  MIN(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS min_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON a.hadm_id = diag.hadm_id
  AND a.subject_id = diag.subject_id
WHERE
  p.gender = 'F'
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 88 AND 98
  AND a.admission_type = 'EMERGENCY'
  AND diag.seq_num = 1  -- Primary diagnosis
  AND (
    (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^(480|481|482|483|484|485|486)'))
    OR
    (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^(J12|J13|J14|J15|J16|J17|J18)'))
  );