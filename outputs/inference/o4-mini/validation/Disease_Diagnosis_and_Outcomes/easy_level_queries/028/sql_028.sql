SELECT
  -- 25th percentile of hospital LOS in days
  APPROX_QUANTILES(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY), 100)[OFFSET(25)] AS p25_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.subject_id = di.subject_id
  AND a.hadm_id = di.hadm_id
  AND di.seq_num = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON di.icd_code = dd.icd_code
  AND di.icd_version = dd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 67 AND 77
  AND a.admission_type = 'EMERGENCY'
  AND LOWER(dd.long_title) LIKE '%pneumonia%'
;