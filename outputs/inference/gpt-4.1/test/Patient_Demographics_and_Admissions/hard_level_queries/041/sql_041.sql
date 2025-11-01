SELECT COUNT(DISTINCT a.hadm_id) AS num_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 80 AND 90
  AND a.insurance = 'Medicare'
  AND (
    LOWER(a.admission_location) LIKE '%emergency%'
    OR LOWER(a.admission_location) LIKE '%ed%'
    OR LOWER(a.admission_location) LIKE '%er%'
  )
  AND d.seq_num = 1
  AND (
    -- ICD-9 osteomyelitis: 730.xx
    (d.icd_version = 9 AND d.icd_code LIKE '730%')
    -- ICD-10 osteomyelitis: M86.xx
    OR (d.icd_version = 10 AND d.icd_code LIKE 'M86%')
  );