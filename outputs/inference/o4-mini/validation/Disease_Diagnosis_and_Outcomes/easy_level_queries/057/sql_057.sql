SELECT
  MIN(
    DATE_DIFF(
      DATE(a.dischtime),
      DATE(a.admittime),
      DAY
    )
  ) AS min_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
USING(subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id
  AND a.hadm_id    = d.hadm_id
  AND d.seq_num    = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON d.icd_code    = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 88 AND 98
  AND a.admission_type = 'EMERGENCY'
  AND LOWER(dd.long_title) LIKE '%pneumonia%';