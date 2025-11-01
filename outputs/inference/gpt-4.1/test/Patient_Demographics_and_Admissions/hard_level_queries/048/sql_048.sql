SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 79 AND 89
  AND a.insurance = 'Medicare'
  AND LOWER(a.admission_location) LIKE '%emergency%'
  AND d.seq_num = 1
  AND (
    -- ICD-10 pneumonia: J12-J18
    (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J1[2-8]'))
    -- ICD-9 pneumonia: 480-486
    OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^48[0-6]'))
  );