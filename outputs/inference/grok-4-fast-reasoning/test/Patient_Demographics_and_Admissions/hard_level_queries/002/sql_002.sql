SELECT COUNT(DISTINCT a.hadm_id) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id AND d.seq_num = 1
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
WHERE p.gender = 'M'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY'
  AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 77 AND 87
  AND icd.long_title LIKE '%pneumonia%';