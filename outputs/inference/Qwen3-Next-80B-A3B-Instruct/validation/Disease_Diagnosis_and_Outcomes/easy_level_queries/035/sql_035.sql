SELECT PERCENTILE_CONT(los_days, 0.75) AS p75_hospital_los_days
FROM (
  SELECT 
    CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS FLOAT64) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 70
    AND d.seq_num = 1
    AND d_icd.long_title LIKE '%upper gastrointestinal hemorrhage%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
) AS filtered_los;