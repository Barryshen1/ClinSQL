SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
  AND d.seq_num = 1
WHERE 
  p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM HOSPITAL'
  AND (
    (d.icd_version = 9 AND d.icd_code LIKE '730%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'M86%')
  )
  AND (
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) 
    BETWEEN 85 AND 95
  );