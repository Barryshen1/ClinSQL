WITH pneumonia_cohort AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
    AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'EMERGENCY'
    AND d.seq_num = 1
    AND LOWER(icd.long_title) LIKE '%pneumonia%'
)

SELECT COUNT(*) AS num_admissions
FROM pneumonia_cohort;