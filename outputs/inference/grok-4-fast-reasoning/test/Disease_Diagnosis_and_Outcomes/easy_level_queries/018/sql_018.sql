SELECT
  STDDEV(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS sd_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON
  a.hadm_id = d.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 45 AND 55
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code LIKE '43%')
    OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
  );