WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    d.seq_num = 1  -- primary diagnosis
    AND (
      (d.icd_version = 10 AND d.icd_code = 'J44.1') 
      OR 
      (d.icd_version = 9 AND d.icd_code = '491.21')
    )
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.dischtime IS NOT NULL  -- exclude ongoing admissions
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile
FROM cohort;