SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25
FROM (
  SELECT TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.seq_num = 1
    AND LOWER(di.long_title) LIKE '%pneumonia%'
    AND LOWER(di.long_title) NOT LIKE '%hospital-acquired%'
    AND LOWER(di.long_title) NOT LIKE '%nosocomial%'
) subquery;