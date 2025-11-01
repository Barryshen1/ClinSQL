WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id 
    AND d.seq_num = 1
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND d.icd_code LIKE 'I50%'
    AND icd.icd_version = 10
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 0  -- Exclude deaths (incomplete LOS)
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
percentiles AS (
  SELECT 
    PERCENTILE_CONT(los_days, 0.25) AS q1_los_days,
    PERCENTILE_CONT(los_days, 0.75) AS q3_los_days
  FROM first_admissions
)
SELECT 
  q1_los_days,
  q3_los_days,
  (q3_los_days - q1_los_days) AS iqr_los_days
FROM percentiles;