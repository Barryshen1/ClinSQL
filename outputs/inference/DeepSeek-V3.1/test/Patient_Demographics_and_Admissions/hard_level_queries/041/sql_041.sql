SELECT COUNT(DISTINCT a.hadm_id) AS count_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
WHERE p.gender = 'F'
  AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 80 AND 90
  AND a.admission_location = 'EMERGENCY ROOM'
  AND a.insurance = 'Medicare'
  AND diag.seq_num = 1
  AND (
      (d.icd_code LIKE 'M86%' AND d.icd_version = 10) 
      OR 
      (d.icd_code LIKE '730%' AND d.icd_version = 9)
  );