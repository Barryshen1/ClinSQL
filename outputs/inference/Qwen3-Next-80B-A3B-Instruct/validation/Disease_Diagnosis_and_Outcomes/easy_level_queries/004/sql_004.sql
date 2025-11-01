SELECT APPROX_QUANTILES(hospital_los, 4)[OFFSET(1)] AS hospital_los_25th_percentile
FROM (
  SELECT DATE_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND d.seq_num = 1
    AND (
      LOWER(d_icd.long_title) LIKE '%diabetic ketoacidosis%'
      OR LOWER(d_icd.long_title) LIKE '%hyperosmolar%'
      OR LOWER(d_icd.long_title) LIKE '%hhs%'
    )
    AND a.dischtime IS NOT NULL
) AS filtered_admissions;