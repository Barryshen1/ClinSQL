SELECT COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
WHERE p.gender = 'M'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER'
  AND a.hospital_expire_flag = 0
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '411.1')
    OR
    (d.icd_version = 10 AND d.icd_code = 'I20.0')
  )
  AND 72 <= (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - 2008))
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - 2008)) <= 82;