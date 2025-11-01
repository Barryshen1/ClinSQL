SELECT COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 36 AND 46
  AND a.insurance = 'Medicare'
  AND LOWER(a.admission_type) = 'transfer from another hospital'
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%')) OR
    (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
  );