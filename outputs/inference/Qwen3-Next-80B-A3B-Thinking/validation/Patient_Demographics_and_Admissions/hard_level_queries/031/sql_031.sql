SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location IN ('Emergency Room Admit', 'Emergency Room')
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '780.2')
    OR (d.icd_version = 10 AND d.icd_code = 'R55')
  )
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 62 AND 72;