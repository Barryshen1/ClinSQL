SELECT
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS avg_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON
  a.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON
  a.subject_id = d.subject_id
  AND a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 61 AND 71
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code LIKE '428%')
    OR
    (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
  )
  AND a.dischtime > a.admittime;