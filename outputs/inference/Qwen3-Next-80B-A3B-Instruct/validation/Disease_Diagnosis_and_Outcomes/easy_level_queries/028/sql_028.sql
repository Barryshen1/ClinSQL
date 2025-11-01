SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_hospital_los_days
FROM (
  SELECT DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.seq_num = 1
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
) AS filtered_los;