SELECT COUNT(DISTINCT a.hadm_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 90 AND 100
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM HOSPITAL'
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '585.6') OR
    (d.icd_version = 10 AND d.icd_code = 'N18.6')
  );