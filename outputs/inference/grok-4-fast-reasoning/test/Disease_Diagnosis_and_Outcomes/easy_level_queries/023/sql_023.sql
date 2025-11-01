SELECT
  APPROX_QUANTILES(
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY),
    2
  )[OFFSET(1)] AS median_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  p.subject_id = a.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON
  a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` i
ON
  d.icd_code = i.icd_code AND d.icd_version = i.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 83 AND 93
  AND d.seq_num = 1
  AND LOWER(i.long_title) LIKE '%pneumonia%'
  AND a.admission_type = 'EMERGENCY'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND a.dischtime > a.admittime  -- Ensure valid LOS (rarely needed but guards against data errors);