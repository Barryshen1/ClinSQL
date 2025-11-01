SELECT PERCENTILE_CONT(los_days, 0.5) WITHIN GROUP (ORDER BY los_days) AS median_hospital_los
FROM (
  SELECT TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND d.seq_num = 1
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
) AS los_calculation;