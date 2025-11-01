SELECT
  PERCENTILE_CONT(los, 0.25) AS p25_los_days
FROM (
  SELECT
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND LOWER(icd.long_title) LIKE '%exacerbation%'
    AND (LOWER(icd.long_title) LIKE '%copd%' OR LOWER(icd.long_title) LIKE '%obstructive%')
    AND a.dischtime > a.admittime  -- Ensure positive LOS
);