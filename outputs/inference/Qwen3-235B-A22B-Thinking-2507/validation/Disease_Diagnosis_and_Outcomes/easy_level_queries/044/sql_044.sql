SELECT
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 61 AND 71
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code LIKE '428%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
  )
  AND a.dischtime IS NOT NULL;