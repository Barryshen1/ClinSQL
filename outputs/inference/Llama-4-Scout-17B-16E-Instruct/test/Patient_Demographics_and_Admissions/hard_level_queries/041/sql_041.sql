WITH osteomyelitis_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Osteomyelitis%'
),
target_patients AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type = 'Emergency'
    AND a.insurance = 'Medicare'
    AND d.seq_num = 1
    AND d.icd_code IN (SELECT icd_code FROM osteomyelitis_icd_codes)
)
SELECT COUNT(DISTINCT hadm_id) AS number_of_admissions
FROM target_patients;