SELECT
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los_days
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 78 AND 88
  AND d.seq_num = 1
  AND (
    -- ICD-10: I20-I25
    (d.icd_version = 10 AND (
      LEFT(d.icd_code, 3) IN ('I20', 'I21', 'I22', 'I23', 'I24', 'I25')
    ))
    -- ICD-9: 410-414
    OR
    (d.icd_version = 9 AND (
      LEFT(d.icd_code, 3) IN ('410', '411', '412', '413', '414')
    ))
  )
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;