SELECT APPROX_QUANTILES(adm.los, 100)[OFFSET(25)] AS p25_los
FROM (
  SELECT 
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.seq_num = 1
    AND (
      LOWER(dicd.long_title) LIKE '%ischemic stroke%'
      OR LOWER(dicd.long_title) LIKE '%cerebral infarction%'
      OR LOWER(dicd.long_title) LIKE '%ischemic cerebrovascular accident%'
    )
) adm;