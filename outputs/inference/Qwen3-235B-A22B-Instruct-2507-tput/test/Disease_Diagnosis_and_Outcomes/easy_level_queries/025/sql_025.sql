SELECT
  STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS los_sd_days
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients pat
JOIN
  `physionet-data.mimiciv_3_1_hosp`.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  pat.anchor_age BETWEEN 77 AND 87
  AND pat.gender = 'M'
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code IN ('5780', '5781', '5789'))
    OR
    (diag.icd_version = 10 AND diag.icd_code IN ('K920', 'K921', 'K922'))
  )
  AND adm.admittime IS NOT NULL
  AND adm.dischtime IS NOT NULL;