SELECT
  MAX(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS max_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id    = d.hadm_id
    AND d.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code    = dicd.icd_code
    AND d.icd_version = dicd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 67 AND 77
  AND (
    LOWER(dicd.long_title) LIKE '%sepsis%' 
    OR LOWER(dicd.long_title) LIKE '%septic shock%'
  );