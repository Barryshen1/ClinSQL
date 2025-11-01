SELECT
  APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR), 4)[OFFSET(2)] AS median_hours,
  APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR), 4)[OFFSET(1)] AS q1_hours,
  APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR), 4)[OFFSET(3)] AS q3_hours,
  APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR), 4)[OFFSET(3)] 
  - APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR), 4)[OFFSET(1)] AS iqr_hours
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 71 AND 81
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '43491')
    OR
    (d.icd_version = 10 AND d.icd_code = 'I639')
  );