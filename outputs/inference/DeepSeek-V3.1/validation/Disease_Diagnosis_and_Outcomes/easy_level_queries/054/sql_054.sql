SELECT
  STDDEV(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS los_stddev_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 51 AND 61
  AND d.icd_version = 10
  AND d.icd_code LIKE 'I6%'
  AND d.seq_num = 1;