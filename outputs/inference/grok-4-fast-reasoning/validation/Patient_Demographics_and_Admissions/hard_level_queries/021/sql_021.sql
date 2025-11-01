SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 82 AND 92
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND a.dischtime IS NOT NULL
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '577.0')
    OR
    (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
  );