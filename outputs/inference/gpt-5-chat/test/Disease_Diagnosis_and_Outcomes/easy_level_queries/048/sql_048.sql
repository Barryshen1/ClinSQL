WITH sepsis_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    -- compute LOS in days with fractional part
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.seq_num = 1
    AND (
      -- ICD-9 sepsis/severe sepsis/septic shock codes
      (d.icd_version = 9 AND (
           d.icd_code LIKE '038%'    -- septicemia
        OR d.icd_code IN ('99591','99592','78552') -- sepsis/severe sepsis/septic shock
      ))
      OR
      -- ICD-10 sepsis/severe sepsis/septic shock codes
      (d.icd_version = 10 AND (
           d.icd_code LIKE 'A40%'    -- streptococcal sepsis
        OR d.icd_code LIKE 'A41%'    -- other sepsis
        OR d.icd_code IN ('R6520','R6521') -- severe sepsis, septic shock
      ))
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT MAX(los_days) AS max_hosp_los_days
FROM sepsis_patients;