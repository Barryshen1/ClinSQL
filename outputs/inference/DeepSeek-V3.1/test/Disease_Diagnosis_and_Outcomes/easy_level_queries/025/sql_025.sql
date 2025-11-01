SELECT
  STDDEV(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS los_stddev_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87
  AND d.seq_num = 1  -- primary diagnosis
  AND d.icd_version = 10
  AND d.icd_code IN (
    'K250', 'K252', 'K254', 'K256',
    'K260', 'K262', 'K264', 'K266',
    'K270', 'K272', 'K274', 'K276',
    'K280', 'K282', 'K284', 'K286',
    'K920', 'K921', 'K922'
  )
  AND a.dischtime IS NOT NULL;  -- exclude ongoing admissions;