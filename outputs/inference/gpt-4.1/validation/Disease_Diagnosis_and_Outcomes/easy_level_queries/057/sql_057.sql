SELECT
  MIN(
    DATE_DIFF(a.dischtime, a.admittime, DAY)
  ) AS min_hospital_los_days
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
  AND p.anchor_age BETWEEN 88 AND 98
  AND d.seq_num = 1
  AND (
    -- ICD-10 pneumonia codes J12-J18
    (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J1[2-8]'))
    -- ICD-9 pneumonia codes 480-486
    OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^48[0-6]'))
  )
  -- Community-acquired: exclude transfers from other hospitals
  AND a.admission_type IN ('EMERGENCY', 'URGENT')
  AND (
    a.admission_location NOT LIKE '%TRANSFER%'
    OR a.admission_location IS NULL
  )
  -- Exclude missing discharge times
  AND a.dischtime IS NOT NULL
  AND a.admittime IS NOT NULL;