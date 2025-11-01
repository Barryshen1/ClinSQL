WITH sepsis_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    -- Calculate LOS in fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE 
    p.gender = 'F'
    -- Compute age at admission using anchor_year and anchor_age
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    AND d.seq_num = 1  -- Primary diagnosis only
    AND (
      -- ICD-10 codes for sepsis/septic shock
      (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code = 'R65.21'))
      OR 
      -- ICD-9 codes for sepsis/septic shock
      (d.icd_version = 9 AND (d.icd_code LIKE '038%' OR d.icd_code = '785.52'))
    )
    -- Ensure valid discharge time
    AND a.dischtime > a.admittime
)
SELECT 
  STDDEV(los_days) AS sd_length_of_stay_days
FROM sepsis_admissions;