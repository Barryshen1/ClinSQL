WITH stroke_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    -- Calculate length of stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND diag.seq_num = 1  -- primary diagnosis
    AND (
      -- ICD-10 codes for hemorrhagic stroke
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I6[0-2]%')
      OR
      -- ICD-9 codes for hemorrhagic stroke
      (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432'))
    )
    AND adm.dischtime > adm.admittime  -- ensure valid LOS
)
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM stroke_admissions;