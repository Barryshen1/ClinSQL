SELECT
  MAX(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS max_hospital_los
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON
  a.subject_id = CAST(d.subject_id AS INT64)
  AND a.hadm_id = CAST(d.hadm_id AS INT64)
WHERE
  p.gender = 'F'
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 67 AND 77
  AND d.seq_num = 1
  AND a.dischtime IS NOT NULL
  AND (
    (d.icd_version = '9' AND (d.icd_code LIKE '038%' OR d.icd_code = '78552'))
    OR
    (d.icd_version = '10' AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R652%'))
  );