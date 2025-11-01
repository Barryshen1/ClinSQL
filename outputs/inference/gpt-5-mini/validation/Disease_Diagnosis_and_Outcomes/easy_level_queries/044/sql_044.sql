SELECT
  COUNT(1) AS n_admissions,
  ROUND(AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0), 2) AS avg_los_days,
  ROUND(STDDEV_POP(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0), 2) AS sd_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
  AND a.subject_id = d.subject_id
  AND d.seq_num = 1  -- primary diagnosis
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
  ON d.icd_code = dicd.icd_code
  AND d.icd_version = dicd.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 61 AND 71
  AND LOWER(dicd.long_title) LIKE '%heart failure%'
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;