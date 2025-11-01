SELECT
  APPROX_QUANTILES(
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY),
    4
  )[OFFSET(1)] AS p25_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  p.subject_id = a.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON
  a.hadm_id = d.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
ON
  d.icd_code = icd.icd_code
  AND d.icd_version = icd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 67 AND 77
  AND d.seq_num = 1
  AND LOWER(icd.long_title) LIKE '%pneumonia%'
  AND a.admission_location = 'EMERGENCY ROOM';