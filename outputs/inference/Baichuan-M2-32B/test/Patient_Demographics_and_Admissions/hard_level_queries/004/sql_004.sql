WITH eligible_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 85 AND 95
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'Transfer from another hospital (Elective)'
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND dd.icd_version = 10
    AND dd.long_title LIKE '%osteomyelitis%'
)
SELECT COUNT(*) AS num_index_admissions
FROM eligible_admissions;