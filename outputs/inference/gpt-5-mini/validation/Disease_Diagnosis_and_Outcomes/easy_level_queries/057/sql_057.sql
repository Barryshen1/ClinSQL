SELECT
  ROUND(
    MIN(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)) / 86400.0
  , 2) AS min_hospital_los_days,
  COUNT(DISTINCT a.hadm_id) AS n_admissions_in_cohort
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
USING (subject_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON a.hadm_id = d.hadm_id
LEFT JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
ON d.icd_code = dicd.icd_code
   AND CAST(dicd.icd_version AS STRING) = CAST(d.icd_version AS STRING)
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 88 AND 98
  -- primary diagnosis (principal/billing diagnosis)
  AND d.seq_num = 1
  -- diagnosis text contains pneumonia (case-insensitive)
  AND (
    LOWER(COALESCE(dicd.long_title, '')) LIKE '%pneumonia%'
    OR LOWER(COALESCE(d.icd_code, '')) LIKE '%pneumonia%'  -- fallback (rare)
  )
  -- proxy for community-acquired: prefer emergency/home admissions; exclude transfers from other hospitals
  AND (
    a.admission_type = 'EMERGENCY'
    OR LOWER(COALESCE(a.admission_location, '')) LIKE '%home%'
    OR LOWER(COALESCE(a.admission_location, '')) LIKE '%ed%'
    OR LOWER(COALESCE(a.admission_location, '')) LIKE '%emergency%'
  )
  AND LOWER(COALESCE(a.admission_location, '')) NOT LIKE '%transfer%'
  AND LOWER(COALESCE(a.admission_location, '')) NOT LIKE '%hospital%'
  -- ensure valid admission/discharge times and non-negative duration
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0;