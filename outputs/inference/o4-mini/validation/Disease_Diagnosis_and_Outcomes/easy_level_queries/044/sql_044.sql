SELECT
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 61 AND 71
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '428'))
    OR
    (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I50'))
  )
  -- Ensure both admittime and dischtime exist to calculate LOS
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;