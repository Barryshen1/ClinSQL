SELECT
  MAX(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS max_los_days
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
  AND d.seq_num = 1  -- Primary diagnosis
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
  AND (  -- Sepsis/septic shock ICD codes
    (d.icd_version = 9 AND d.icd_code IN ('99591', '99592', '78552'))
    OR
    (d.icd_version = 10 AND d.icd_code IN ('A41', 'R65.20', 'R65.21'))
  );