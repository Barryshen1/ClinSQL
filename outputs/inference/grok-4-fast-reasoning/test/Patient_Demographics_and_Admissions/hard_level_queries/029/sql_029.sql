SELECT COUNT(DISTINCT a.hadm_id) AS num_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` i
  ON d.icd_code = i.icd_code AND d.icd_version = i.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 46 AND 56
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM HOSP'
  AND d.seq_num = 1
  AND i.long_title LIKE '%hip%fracture%';