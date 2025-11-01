SELECT STDDEV_POP(los_days) AS std_dev_los
FROM (
  SELECT
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 45 AND 55
    AND d.seq_num = 1
    AND (
      (d.icd_version = '9' AND d.icd_code IN ('430', '431', '432'))
      OR
      (d.icd_version = '10' AND d.icd_code IN ('I60', 'I61', 'I62'))
    )
) subquery;