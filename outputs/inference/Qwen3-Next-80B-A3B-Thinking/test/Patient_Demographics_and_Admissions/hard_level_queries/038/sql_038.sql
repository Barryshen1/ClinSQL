SELECT COUNT(*) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
WHERE d.seq_num = 1
  AND a.admission_type = 'transfer from another hospital'
  AND a.insurance = 'Medicare'
  AND p.gender = 'M'
  AND (
    (d.icd_version = 9 AND d.icd_code = '585.6')
    OR (d.icd_version = 10 AND d.icd_code = 'N18.6')
  )
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 90 AND 100;