WITH sepsis_patients AS (
  -- Get female patients aged 67-77 with primary sepsis/septic shock diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-9 codes for sepsis/septic shock
      (d.icd_version = 9 AND d.icd_code IN ('99591', '78552'))
      OR
      -- ICD-10 codes for sepsis/septic shock
      (d.icd_version = 10 AND d.icd_code IN ('R6520', 'R6521', 'A419', 'A4152'))
    )
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths
)

-- Calculate standard deviation of LOS
SELECT
  STDDEV(los_days) AS sd_los_days
FROM
  sepsis_patients
WHERE
  los_days IS NOT NULL;