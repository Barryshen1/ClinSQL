SELECT
  MAX(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS max_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
    AND d.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 84 AND 94
  AND LOWER(dd.long_title) LIKE '%ischemic stroke%'
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;