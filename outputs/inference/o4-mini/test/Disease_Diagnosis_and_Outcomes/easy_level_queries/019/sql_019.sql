SELECT
  STDDEV_SAMP(
    DATE_DIFF(
      DATE(adm.dischtime),
      DATE(adm.admittime),
      DAY
    )
  ) AS sd_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  USING(subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  USING(subject_id, hadm_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddiag
  ON diag.icd_code = ddiag.icd_code
  AND diag.icd_version = ddiag.icd_version
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 67 AND 77
  AND diag.seq_num = 1
  AND REGEXP_CONTAINS(ddiag.long_title, r'(?i)sepsis')
;