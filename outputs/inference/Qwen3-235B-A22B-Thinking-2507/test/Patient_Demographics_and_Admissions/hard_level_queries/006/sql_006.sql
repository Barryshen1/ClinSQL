WITH candidate_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
),
hemorrhagic_admissions AS (
  SELECT 
    ca.subject_id,
    ca.hadm_id,
    ca.admittime
  FROM candidate_admissions ca
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ca.hadm_id = d.hadm_id 
    AND ca.subject_id = d.subject_id
  WHERE ca.age_at_admission BETWEEN 36 AND 46
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431'))
      OR 
      (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%'))
    )
),
index_admissions AS (
  SELECT 
    subject_id,
    MIN(admittime) AS first_admittime
  FROM hemorrhagic_admissions
  GROUP BY subject_id
)
SELECT COUNT(*) AS total_index_admissions
FROM index_admissions;