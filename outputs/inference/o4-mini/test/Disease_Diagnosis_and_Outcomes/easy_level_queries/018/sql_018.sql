SELECT
  STDDEV_SAMP(
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0
  ) AS sd_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
ON
  a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
ON
  a.hadm_id = d.hadm_id
WHERE
  d.seq_num = 1
  AND d.icd_version = 9
  AND d.icd_code IN ('430', '431')               -- hemorrhagic stroke ICD-9 codes
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 45 AND 55
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;