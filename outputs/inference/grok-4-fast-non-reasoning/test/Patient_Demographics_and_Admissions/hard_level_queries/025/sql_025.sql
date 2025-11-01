WITH cohort AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
    AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'TRANSFER'
    AND d.seq_num = 1
    AND d.icd_version = 9
    AND LOWER(icd.long_title) LIKE '%heart failure%'
)
SELECT COUNT(hadm_id) AS num_index_admissions
FROM cohort;