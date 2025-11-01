SELECT
  STDDEV_SAMP(
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0
  ) AS sd_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON a.subject_id = di.subject_id
  AND a.hadm_id = di.hadm_id
  AND di.seq_num = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON di.icd_code = dd.icd_code
  AND di.icd_version = dd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 51 AND 61
  AND LOWER(dd.long_title) LIKE '%hemorrhag%'
  AND LOWER(dd.long_title) LIKE '%stroke%'
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;