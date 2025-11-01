WITH filtered_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER'
    AND a.dischtime IS NOT NULL
    AND d.seq_num = 1
    AND d.icd_code IN ('I20.0', '411.1')  -- I20.0 (ICD-10 unstable angina), 411.1 (ICD-9)
)
SELECT COUNT(hadm_id) AS total_admissions
FROM filtered_admissions;