SELECT MAX(
  TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0
) AS max_los_days
FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON p.subject_id = adm.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
WHERE p.gender = 'M'
  AND (
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)
  ) BETWEEN 84 AND 94
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 10 AND diag.icd_code LIKE 'I63.%')
    OR (diag.icd_version = 9 AND diag.icd_code IN (
      '43491', '43301', '43311', '43321', '43331', 
      '43381', '43391', '43401', '43411'
    ))
  )
  AND adm.dischtime >= adm.admittime;