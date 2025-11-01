SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND a.insurance = 'Medicare'
  AND (
    LOWER(a.admission_location) LIKE '%skilled nursing%'
    OR LOWER(a.admission_location) LIKE '%snf%'
  )
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '27651') -- ICD-9 dehydration
    OR
    (d.icd_version = 10 AND d.icd_code = 'E860') -- ICD-10 dehydration
  );