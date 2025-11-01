SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 65 AND 75
  AND LOWER(a.insurance) LIKE 'medicare%'
  AND a.admission_type = 'TRANSFER'
  AND LOWER(a.admission_location) LIKE '%hospital%'
  AND d.seq_num = 1
  AND (
    (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
  );