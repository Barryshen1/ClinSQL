SELECT COUNT(DISTINCT a.hadm_id) AS num_qualifying_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND d.seq_num = 1
  AND icd.long_title LIKE '%ketoacidosis%';