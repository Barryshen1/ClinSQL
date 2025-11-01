SELECT
  MAX(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS max_hospital_los_days
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 67 AND 77
  AND d.seq_num = 1
  AND (
    -- ICD-10 sepsis/septic shock
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'A40%' OR
      d.icd_code LIKE 'A41%' OR
      d.icd_code LIKE 'R652%'
    ))
    -- ICD-9 sepsis/septic shock
    OR (d.icd_version = 9 AND (
      d.icd_code IN ('99591', '99592', '78552')
    ))
  )
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;