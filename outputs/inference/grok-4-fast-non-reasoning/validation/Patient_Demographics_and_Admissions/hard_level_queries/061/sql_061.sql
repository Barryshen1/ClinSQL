WITH cohort AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'HOSP-TRANSFER'
    AND d.seq_num = CAST(1 AS INT64)
    AND d.icd_version = 10
    AND d.icd_code = 'I48'
)
SELECT COUNT(*) AS total_admissions
FROM cohort;